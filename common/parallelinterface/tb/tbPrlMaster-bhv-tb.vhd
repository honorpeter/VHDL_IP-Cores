-------------------------------------------------------------------------------
--! @file tbPrlMaster-bhv-tb.vhd
--
--! @brief Testbench for Multiplex parallel master ipcore
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

--! Use standard ieee library
library ieee;
--! Use logic elements
use ieee.std_logic_1164.all;

--! Utility library
library libutil;

--! Use libcommon library
library libcommon;
--! Use global package
use libcommon.global.all;

entity tbPrlMaster is
    generic (
        gEnableMux  : natural := 0;
        gStim       : string := "text.txt"
    );
end tbPrlMaster;

architecture bhv of tbPrlMaster is
    signal clk  : std_logic;
    signal rst  : std_logic;
    signal done : std_logic;

    constant cAddrWidth : natural := 6;
    constant cDataWidth : natural := 32;
    constant cAdWidth   : natural := maximum(cAddrWidth, cDataWidth);

    -- Multiplex master
    type tPrlMaster is record
        slv_address     : std_logic_vector(cAddrWidth-1 downto 0);
        slv_read        : std_logic;
        slv_readdata    : std_logic_vector(cDataWidth-1 downto 0);
        slv_write       : std_logic;
        slv_writedata   : std_logic_vector(cDataWidth-1 downto 0);
        slv_waitrequest : std_logic;
        slv_byteenable  : std_logic_vector(cDataWidth/8-1 downto 0);
        prlMst_cs       : std_logic;
        prlMst_ad_i     : std_logic_vector(cAdWidth-1 downto 0);
        prlMst_ad_o     : std_logic_vector(cAdWidth-1 downto 0);
        prlMst_ad_oen   : std_logic;
        prlMst_addr     : std_logic_vector(cAddrWidth-1 downto 0);
        prlMst_data_i   : std_logic_vector(cDataWidth-1 downto 0);
        prlMst_data_o   : std_logic_vector(cDataWidth-1 downto 0);
        prlMst_data_oen : std_logic;
        prlMst_be       : std_logic_vector(cDataWidth/8-1 downto 0);
        prlMst_ale      : std_logic;
        prlMst_wr       : std_logic;
        prlMst_rd       : std_logic;
        prlMst_ack      : std_logic;
    end record;

    signal inst_prlMaster : tPrlMaster;

    -- multiplexed slave
    type tPrlSlave is record
        prlSlv_cs       : std_logic;
        prlSlv_rd       : std_logic;
        prlSlv_wr       : std_logic;
        prlSlv_ale      : std_logic;
        prlSlv_ack      : std_logic;
        prlSlv_be       : std_logic_vector(cDataWidth/8-1 downto 0);
        prlSlv_ad_i     : std_logic_vector(cAdWidth-1 downto 0);
        prlSlv_ad_o     : std_logic_vector(cAdWidth-1 downto 0);
        prlSlv_ad_oen   : std_logic;
        prlSlv_addr     : std_logic_vector(cAddrWidth-1 downto 0);
        prlSlv_data_i   : std_logic_vector(cAdWidth-1 downto 0);
        prlSlv_data_o   : std_logic_vector(cAdWidth-1 downto 0);
        prlSlv_data_oen : std_logic;
        mst_chipselect  : std_logic;
        mst_read        : std_logic;
        mst_write       : std_logic;
        mst_byteenable  : std_logic_vector(cDataWidth/8-1 downto 0);
        mst_address     : std_logic_vector(cAddrWidth-1 downto 0);
        mst_writedata   : std_logic_vector(cDataWidth-1 downto 0);
        mst_readdata    : std_logic_vector(cDataWidth-1 downto 0);
        mst_waitrequest : std_logic;
    end record;

    signal inst_prlSlave : tPrlSlave;

    -- Single port ram
    type tSpram is record
        write       : std_logic;
        read        : std_logic;
        address     : std_logic_vector(cAddrWidth-1 downto 0);
        byteenable  : std_logic_vector(cDataWidth/8-1 downto 0);
        writedata   : std_logic_vector(cDataWidth-1 downto 0);
        readdata    : std_logic_vector(cDataWidth-1 downto 0);
        ready       : std_logic;
    end record;

    signal inst_spram : tSpram;

    -- Stim bus master
    type tBusMaster is record
        ack        : std_logic;
        enable     : std_logic;
        readdata   : std_logic_vector(cDataWidth-1 downto 0);
        address    : std_logic_vector(cAddrWidth-1 downto 0);
        byteenable : std_logic_vector(cDataWidth/8-1 downto 0);
        done       : std_logic;
        error      : std_logic;
        read       : std_logic;
        write      : std_logic;
        writedata  : std_logic_vector(cDataWidth-1 downto 0);
    end record;

    signal inst_busMaster : tBusMaster;
begin
    done                    <= inst_busMaster.done;
    inst_busMaster.enable   <= cActivated;

    assert (inst_busMaster.error /= cActivated)
    report "Bus master reports error!" severity failure;

    ---------------------------------------------------------------------------
    -- Map components

    -- inst_busMaster --- inst_prlMaster
    inst_prlMaster.slv_read     <= inst_busMaster.read;
    inst_prlMaster.slv_write    <= inst_busMaster.write;
    inst_busMaster.ack          <= not inst_prlMaster.slv_waitrequest;

    inst_prlMaster.slv_address      <= inst_busMaster.address(inst_prlMaster.slv_address'range);
    inst_prlMaster.slv_byteenable   <= inst_busMaster.byteenable;
    inst_prlMaster.slv_writedata    <= inst_busMaster.writedata(inst_prlMaster.slv_writedata'range);
    inst_busMaster.readdata         <= inst_prlMaster.slv_readdata;

    -- inst_prlMaster --- inst_prlSlave
    inst_prlSlave.prlSlv_cs     <= inst_prlMaster.prlMst_cs;
    inst_prlSlave.prlSlv_rd     <= inst_prlMaster.prlMst_rd;
    inst_prlSlave.prlSlv_wr     <= inst_prlMaster.prlMst_wr;
    inst_prlSlave.prlSlv_ale    <= inst_prlMaster.prlMst_ale;
    inst_prlMaster.prlMst_ack   <= inst_prlSlave.prlSlv_ack;

    inst_prlSlave.prlSlv_be     <= inst_prlMaster.prlMst_be;

    -- MUX
    inst_prlMaster.prlMst_ad_i  <=  inst_prlSlave.prlSlv_ad_o when inst_prlSlave.prlSlv_ad_oen = cActivated else
                                    (others => 'Z');

    inst_prlSlave.prlSlv_ad_i   <=  inst_prlMaster.prlMst_ad_o when inst_prlMaster.prlMst_ad_oen = cActivated else
                                    (others => 'Z');

    -- DEMUX
    inst_prlSlave.prlSlv_addr   <=  inst_prlMaster.prlMst_addr;

    inst_prlSlave.prlSlv_data_i <=  inst_prlMaster.prlMst_data_o when inst_prlMaster.prlMst_data_oen = cActivated else
                                    (others => 'Z');

    inst_prlMaster.prlMst_data_i <= inst_prlSlave.prlSlv_data_o when inst_prlSlave.prlSlv_data_oen = cActivated else
                                    (others => 'Z');

    -- inst_prlSlave --- inst_spram
    inst_spram.write        <= inst_prlSlave.mst_write;
    inst_spram.read         <= inst_prlSlave.mst_read;

    inst_prlSlave.mst_waitrequest   <= not inst_spram.ready;
    inst_prlSlave.mst_readdata      <= inst_spram.readdata;

    inst_spram.byteenable   <= inst_prlSlave.mst_byteenable;
    inst_spram.writedata    <= inst_prlSlave.mst_writedata;
    inst_spram.address      <= inst_prlSlave.mst_address;

    ---------------------------------------------------------------------------

    DUT_master : entity work.prlMaster
        generic map (
            gEnableMux      => gEnableMux,
            gDataWidth      => cDataWidth,
            gAddrWidth      => cAddrWidth,
            gAdWidth        => cAdWidth
        )
        port map (
            iClk                => clk,
            iRst                => rst,
            iSlv_address        => inst_prlMaster.slv_address,
            iSlv_read           => inst_prlMaster.slv_read,
            oSlv_readdata       => inst_prlMaster.slv_readdata,
            iSlv_write          => inst_prlMaster.slv_write,
            iSlv_writedata      => inst_prlMaster.slv_writedata,
            oSlv_waitrequest    => inst_prlMaster.slv_waitrequest,
            iSlv_byteenable     => inst_prlMaster.slv_byteenable,
            oPrlMst_cs          => inst_prlMaster.prlMst_cs,
            iPrlMst_ad_i        => inst_prlMaster.prlMst_ad_i,
            oPrlMst_ad_o        => inst_prlMaster.prlMst_ad_o,
            oPrlMst_ad_oen      => inst_prlMaster.prlMst_ad_oen,
            oPrlMst_addr        => inst_prlMaster.prlMst_addr,
            iPrlMst_data_i      => inst_prlMaster.prlMst_data_i,
            oPrlMst_data_o      => inst_prlMaster.prlMst_data_o,
            oPrlMst_data_oen    => inst_prlMaster.prlMst_data_oen,
            oPrlMst_be          => inst_prlMaster.prlMst_be,
            oPrlMst_ale         => inst_prlMaster.prlMst_ale,
            oPrlMst_wr          => inst_prlMaster.prlMst_wr,
            oPrlMst_rd          => inst_prlMaster.prlMst_rd,
            iPrlMst_ack         => inst_prlMaster.prlMst_ack
        );

    DUT_slave : entity work.prlSlave
        generic map (
            gEnableMux      => gEnableMux,
            gDataWidth      => cDataWidth,
            gAddrWidth      => cAddrWidth,
            gAdWidth        => cAdWidth
        )
        port map (
            iClk                => clk,
            iRst                => rst,
            iPrlSlv_cs          => inst_prlSlave.prlSlv_cs,
            iPrlSlv_rd          => inst_prlSlave.prlSlv_rd,
            iPrlSlv_wr          => inst_prlSlave.prlSlv_wr,
            iPrlSlv_ale         => inst_prlSlave.prlSlv_ale,
            oPrlSlv_ack         => inst_prlSlave.prlSlv_ack,
            iPrlSlv_be          => inst_prlSlave.prlSlv_be,
            oPrlSlv_ad_o        => inst_prlSlave.prlSlv_ad_o,
            iPrlSlv_ad_i        => inst_prlSlave.prlSlv_ad_i,
            oPrlSlv_ad_oen      => inst_prlSlave.prlSlv_ad_oen,
            iPrlSlv_addr        => inst_prlSlave.prlSlv_addr,
            iPrlSlv_data_i      => inst_prlSlave.prlSlv_data_i,
            oPrlSlv_data_o      => inst_prlSlave.prlSlv_data_o,
            oPrlSlv_data_oen    => inst_prlSlave.prlSlv_data_oen,
            oMst_address        => inst_prlSlave.mst_address,
            oMst_byteenable     => inst_prlSlave.mst_byteenable,
            oMst_read           => inst_prlSlave.mst_read,
            iMst_readdata       => inst_prlSlave.mst_readdata,
            oMst_write          => inst_prlSlave.mst_write,
            oMst_writedata      => inst_prlSlave.mst_writedata,
            iMst_waitrequest    => inst_prlSlave.mst_waitrequest
        );

    theRam : entity libutil.spRam
        generic map (
            gDataWidth  => inst_spram.writedata'length,
            gAddrWidth  => inst_spram.address'length
        )
        port map (
            iRst        => rst,
            iClk        => clk,
            iWrite      => inst_spram.write,
            iRead       => inst_spram.read,
            iAddress    => inst_spram.address,
            iByteenable => inst_spram.byteenable,
            iWritedata  => inst_spram.writedata,
            oReaddata   => inst_spram.readdata,
            oAck        => inst_spram.ready
        );

    theBusMaster : entity libutil.busMaster
        generic map (
            gAddrWidth      => inst_busMaster.address'length,
            gDataWidth      => inst_busMaster.writedata'length,
            gStimuliFile    => gStim
        )
        port map(
            iClk        => clk,
            iRst        => rst,
            iAck        => inst_busMaster.ack,
            iEnable     => inst_busMaster.enable,
            iReaddata   => inst_busMaster.readdata,
            oAddress    => inst_busMaster.address,
            oByteenable => inst_busMaster.byteenable,
            oDone       => inst_busMaster.done,
            oError      => inst_busMaster.error,
            oRead       => inst_busMaster.read,
            oWrite      => inst_busMaster.write,
            oWritedata  => inst_busMaster.writedata
        );

    theClkGen : entity libutil.clkgen
        generic map (
            gPeriod => 10 ns
        )
        port map (
            iDone   => done,
            oClk    => clk
        );

    theRstGen : entity libutil.resetGen
        generic map (
            gResetTime => 100 ns
        )
        port map (
            oReset  => rst,
            onReset => open
        );
end bhv;
