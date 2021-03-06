-------------------------------------------------------------------------------
--! @file busMasterBhv.vhd
--
--! @brief Behavioral design of the busMaster
--
--! @details This design is used to stimualte bus slaves with a stimulation file
--! in the .txt file format. This file contains instructions, which will be
--! interpreted by the busMasterBhv. The supported instructions are defined
--! in the busMasterPkg. One intstruction per line can be excecuted
--! per clock cycle! For further information refer to busMasterPkg.vhd
--
-------------------------------------------------------------------------------
-- Entity : busMaster
-------------------------------------------------------------------------------
--
--    (c) B&R, 2014
--
--    Redistribution and use in source and binary forms, with or without
--    modification, are permitted provided that the following conditions
--    are met:
--
--    1. Redistributions of source code must retain the above copyright
--       notice, this list of conditions and the following disclaimer.
--
--    2. Redistributions in binary form must reproduce the above copyright
--       notice, this list of conditions and the following disclaimer in the
--       documentation and/or other materials provided with the distribution.
--
--    3. Neither the name of B&R nor the names of its
--       contributors may be used to endorse or promote products derived
--       from this software without prior written permission. For written
--       permission, please contact office@br-automation.com
--
--    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
--    "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
--    LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
--    FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
--    COPYRIGHT HOLDERS OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
--    INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
--    BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
--    LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
--    CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
--    LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
--    ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
--    POSSIBILITY OF SUCH DAMAGE.
--
-------------------------------------------------------------------------------

library std;
use std.textio.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_textio.all;

--! Common library
library libcommon;
--! Use common library global package
use libcommon.global.all;

library libutil;
use libutil.busMasterPkg.all;

entity busMaster is
    generic (
        gAddrWidth      : integer := 32;
        gDataWidth      : integer := 32;
        gStimuliFile    : string := "name_TB_stim.txt"
    );
    port (
        iRst        : in std_logic;
        iClk        : in std_logic;
        iEnable     : in std_logic;
        iAck        : in std_logic;     -- slave says: on write- if have read data; on read- data are now valid!
        iReaddata   : in std_logic_vector(gDataWidth-1 downto 0);
        oWrite      : out std_logic;
        oRead       : out std_logic;
        oSelect     : out std_logic;
        oAddress    : out std_logic_vector(gAddrWidth-1 downto 0);
        oByteenable : out std_logic_vector(gDataWidth/8-1 downto 0);
        oWritedata  : out std_logic_vector(gDataWidth-1 downto 0);
        oError      : out std_logic;
        oDone       : out std_logic
    );
    begin
        assert gDataWidth = cMaxBitWidth report "other bit widths are not yet supported" &
            "by the package! Use a bus converter after the busMaster" &
            "to access slaves with smaller data widths!" severity error;

end busMaster;

architecture bhv of busMaster is
    --***********************************************************************--
    -- TYPES, RECORDS and CONSTANTS:
    --***********************************************************************--
    constant cRelativJumpRange  : natural := 63;
    constant cInitBusProtocol   : tBusProtocol :=(
        command     => s_UNDEF,
        memAccess   => s_UNDEF,
        address     => (others => '0'),
        value1      => (others => '0'),
        value2      => (others => '0')
    );

    type tInterpreterStates is (
        s_HOLDOFF,
        s_READOUT,
        s_INIT_REG,
        s_INSTR_FETCH,
        s_REGISTER,        -- sync. barrier
        s_WAIT,
        s_PRE_COMPARE,     -- glitch barrier
        s_COMPARE,
        s_ERROR,
        s_FINISHED
    );

     type tRegSet is record
        writeEnable         : std_logic;
        readEnable          : std_logic;
        selectEnable        : std_logic;
        address             : std_logic_vector(gAddrWidth-1 downto 0);
        byteEnable          : std_logic_vector(gDataWidth/8-1 downto 0);
        writeData           : std_logic_vector(gDataWidth-1 downto 0);
        compareValue        : std_logic_vector(gDataWidth-1 downto 0);
        relativeJump        : natural;
        doneEnable          : std_logic;
        errorEnable         : std_logic;
        command             : tCommand;
        memAccess           : tMemoryAccess;
    end record tRegSet;

    constant cInitRegSet : tRegSet :=(
        writeEnable             => cInactivated,
        readEnable              => cInactivated,
        selectEnable            => cInactivated,
        address                 => (others => cInactivated),
        byteEnable              => (others => cInactivated),
        writeData               => (others => cInactivated),
        compareValue            => (others => cInactivated),
        relativeJump            => 0,
        doneEnable              => cInactivated,
        errorEnable             => cInactivated,
        command                 => s_UNDEF,
        memAccess               => s_UNDEF
    );
    --***********************************************************************--
    -- SIGNALS:
    --***********************************************************************--
    file stimulifile            : text;

    signal Reg, NextReg         : tRegSet;
    signal InterpreterState     : tInterpreterStates := s_HOLDOFF;
    signal fsmTrigger           : std_logic := '0';

    shared variable vLine       : line;
    shared variable vReadString : string(1 to cMaxLineLength);
    shared variable vCmd        : tCommand;
    shared variable vJump       : boolean := FALSE;

begin
    --! This process opens the stimuli file and stops simulation in case of
    --! failure.
    OPEN_STIM_FILE : process
        variable fileOpenStatus : FILE_OPEN_STATUS;
    begin
        file_open(fileOpenStatus, stimulifile, gStimuliFile, READ_MODE);

        if fileOpenStatus = OPEN_OK then
            assert (FALSE)
                report "Open file " & gStimuliFile & " successfully"
                severity note;
        else
            assert (FALSE)
                report "Open file " & gStimuliFile & " failed!"
                severity failure;
        end if;
        wait;
    end process OPEN_STIM_FILE;

    FSM: process(InterpreterState, Reg, iEnable, iAck, iReaddata, fsmTrigger )
        variable vLine      : line;
        variable vCntLine   : natural := 0;
        variable vAddress   : std_logic_vector(gAddrWidth-1 downto 0);
        variable vValue     : std_logic_vector(gDataWidth-1 downto 0);
        variable vMemAccess : tMemoryAccess;
        variable vNrBytes   : natural;
    begin
        --default assignment:
         -- NextReg <= Reg;
        -- is not possible as the current signal driver would to be overwritten -> latches

        case InterpreterState is
            when s_HOLDOFF =>
                NextReg <= cInitRegSet;
                if iEnable = cActivated then
                    InterpreterState <= s_READOUT;
                end if;

            when s_READOUT =>

                if endfile(stimulifile) then                    -- EOF
                    InterpreterState <= s_FINISHED;
                elsif iEnable = cActivated then                 -- !EOF and iEnable
                    InterpreterState <= s_INIT_REG;
                    if vJump = TRUE then                        -- skip intructions
                        for i in 0 to Reg.relativeJump-1 loop
                            readline(stimulifile, vLine);
                            vCntLine := vCntLine + 1;
                            if endfile(stimulifile) then
                                InterpreterState <= s_ERROR;    -- file is not terminated by an FIN instruction
                                exit;
                            end if;
                        end loop;
                    else
                        readline(stimulifile, vLine);            -- read instruction
                        vCntLine := vCntLine + 1;
                    end if;
                end if;

            when s_INIT_REG =>
                InterpreterState    <= s_INSTR_FETCH;

                vReadString := (others => ' ');
                read(vLine, vReadString(vLine'range));
                -- interpret instruction:
                vCmd                := instruction2Command(vReadString);
                vJump               := FALSE;
                -- reset register
                NextReg.address     <= (others => cInactivated);
                NextReg.writeData   <= (others => cInactivated);
                NextReg.byteEnable  <= (others => cInactivated);
                NextReg.compareValue<= (others => cInactivated);
                NextReg.memAccess   <= s_UNDEF;
                NextReg.command     <= s_UNDEF;
                NextReg.errorEnable <= cInactivated;
                NextReg.doneEnable  <= cInactivated;
                NextReg.writeEnable <= cInactivated;
                NextReg.readEnable  <= cInactivated;
                NextReg.selectEnable<= cInactivated;
                NextReg.relativeJump<= 0;

            when s_INSTR_FETCH  =>
                InterpreterState    <= s_READOUT;               -- read a new line!
                if vCmd /= s_UNDEF then
                    NextReg.command     <= vCmd;
                    vMemAccess          := instruction2MemAccess(vReadString);
                    NextReg.memAccess   <= vMemAccess;
                end if;

                case vCmd is
                    when s_WRITE =>
                        vAddress            := instruction2Value( vReadString, nrBytes2MemAccess( gDataWidth/8 ), 1 )(gAddrWidth-1 downto 0);
                        NextReg.byteEnable  <= MemAccess2ByteEnable( vMemAccess, vAddress );
                        NextReg.address     <= vAddress;
                        vValue              := instruction2Value( vReadString, vMemAccess, 2 );
                        NextReg.writeData   <= value2MaskedValue( vValue, MemAccess2ByteEnable( vMemAccess, vAddress ), MemAccess2nrBytes( vMemAccess ) )(gDataWidth-1 downto 0);
                        NextReg.writeEnable <= cActivated;
                        NextReg.selectEnable<= cActivated;
                        InterpreterState    <= s_REGISTER;

                    when s_READ =>
                        vAddress            := instruction2Value( vReadString, nrBytes2MemAccess( gDataWidth/8 ), 1 )(gAddrWidth-1 downto 0);
                        NextReg.byteEnable  <= MemAccess2ByteEnable( vMemAccess, vAddress );
                        NextReg.address     <= vAddress;
                        NextReg.readEnable  <= cActivated;
                        NextReg.selectEnable<= cActivated;
                        InterpreterState    <= s_REGISTER;

                    when s_JMPEQ | s_JMPNEQ | s_ASSERT | s_WAIT =>
                        vAddress            := instruction2Value( vReadString, nrBytes2MemAccess( gDataWidth/8 ), 1 )(gAddrWidth-1 downto 0);
                        NextReg.byteEnable  <= MemAccess2ByteEnable( vMemAccess, vAddress );
                        NextReg.address     <= vAddress;
                        NextReg.readEnable  <= cActivated;
                        NextReg.selectEnable<= cActivated;
                        vValue              := instruction2Value( vReadString, vMemAccess, 2 )(gDataWidth-1 downto 0);
                        NextReg.compareValue<= value2MaskedValue( vValue, MemAccess2ByteEnable( vMemAccess, vAddress ), MemAccess2nrBytes( vMemAccess ) )(gDataWidth-1 downto 0);
                        InterpreterState    <= s_REGISTER;

                        if vCmd = s_JMPEQ or vCmd = s_JMPNEQ then
                            NextReg.relativeJump <= to_integer(unsigned(instruction2Value( vReadString, nrBytes2MemAccess( gDataWidth/8 ), 3 )));
                        end if;

                    when s_ERROR =>
                        InterpreterState    <= s_ERROR;
                        NextReg.errorEnable <= cActivated;

                    when s_FINISHED =>
                        InterpreterState    <= s_FINISHED;
                        NextReg.doneEnable  <= cActivated;

                    when s_NOP =>
                        InterpreterState    <= s_REGISTER;      -- wait explicit a cycle!

                    when s_UNDEF  =>

                    when others =>
                        assert false report "Undefined tCommand!" severity ERROR;

                end case;
                -- now the values of the NextReg should be stable

            when s_REGISTER =>
                    if fsmTrigger'event then                    -- now stable values are registered
                        InterpreterState <= s_WAIT after 10 ps;
                    end if;

            when s_WAIT =>
                    if iAck = cActivated then
                        -- propagation delay to ensure, that the input is correct.
                        -- otherwise it would take some delta cycles.
                        InterpreterState <= s_PRE_COMPARE after 100 ps;
                    elsif Reg.command = s_NOP then
                        InterpreterState <= s_READOUT;
                    end if;

            when s_PRE_COMPARE =>
                -- check if ack is stable
                if iAck = cActivated then
                    -- stable, go ahead!
                    InterpreterState <= s_COMPARE;
                else
                    -- instable go back
                    InterpreterState <= s_WAIT;
                end if;

            when s_COMPARE =>
                -- compare, if neccessary, actual with compare value!
                InterpreterState    <= s_READOUT;

                case Reg.command is
                    when s_JMPEQ  =>
                        vJump := compareReadValue( iReaddata, Reg.compareValue, Reg.byteEnable );

                    when s_JMPNEQ =>
                        if compareReadValue( iReaddata, Reg.compareValue, Reg.byteEnable ) = FALSE  then
                            vJump := TRUE;
                        end if;

                    when s_ASSERT =>
                        if compareReadValue( iReaddata, Reg.compareValue, Reg.byteEnable ) = FALSE then
                            InterpreterState <= s_ERROR;
                        end if;

                    when s_WAIT =>
                        if compareReadValue( iReaddata, Reg.compareValue, Reg.byteEnable ) = FALSE then
                            NextReg <= Reg;
                            InterpreterState <= s_REGISTER;     -- wait until condition is fulfilled
                        end if;

                    when others   =>
                end case;

                if vJump = TRUE and Reg.relativeJump = 0 then   -- steady state:
                    InterpreterState <= s_FINISHED;
                end if;

            when s_ERROR        =>
                NextReg.errorEnable <= cActivated;
                InterpreterState    <= s_FINISHED;
                assert (FALSE)
                    report  "Hit assert in file " & gStimuliFile &
                            " line " & integer'image(vCntLine) & "."
                    severity error;

            when s_FINISHED     =>
                NextReg.doneEnable <= cActivated;

            when others =>
                    assert false report "Undefined tInterpreterStates!" severity ERROR;
        end case; -- InterpreterState

    end process FSM;

    --***********************************************************************--
    -- REGISTERING:
    --***********************************************************************--
    Registering: process(iClk, iRst)
    begin
        if iRst = cActivated then
            Reg <= cInitRegSet;
        elsif iClk'event and iClk = cActivated then
            Reg <= NextReg;
            fsmTrigger <= not fsmTrigger;
        end if;
    end process Registering;

    --***********************************************************************--
    -- OUTPUT ASSIGNMENTS:
    --***********************************************************************--
    oWrite      <= Reg.writeEnable;
    oRead       <= Reg.readEnable;
    oSelect     <= Reg.selectEnable;
    oAddress    <= Reg.address(gAddrWidth-1 downto 0);
    oByteenable <= Reg.byteEnable;
    oWritedata  <= Reg.writeData(gDataWidth-1 downto 0);
    oError      <= Reg.errorEnable;
    oDone       <= Reg.doneEnable;

end bhv;