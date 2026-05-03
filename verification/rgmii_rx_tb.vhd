--------------------------------------------------------------------------------
-- rgmii_rx_tb
--
-- Drives ten bytes (0x01..0x0A) onto the RGMII RX pins as DDR nibbles
-- (low nibble on rising edge, high nibble on falling edge of rgmii_rxc) with
-- rgmii_rx_ctl held high for the duration. Lets the simulator show that
-- rx_data reassembles each byte and rx_data_valid goes high.
--
-- 125 MHz simulated rgmii_rxc.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity rgmii_rx_tb is
end entity rgmii_rx_tb;

architecture sim of rgmii_rx_tb is

    signal rst          : std_logic                    := '0';
    signal rgmii_rxc    : std_logic                    := '0';
    signal rgmii_rxd    : std_logic_vector(3 downto 0) := (others => '0');
    signal rgmii_rx_ctl : std_logic                    := '0';

    signal rx_data_clk   : std_logic;
    signal rx_data       : std_logic_vector(7 downto 0);
    signal rx_data_valid : std_logic;
    signal rx_data_err   : std_logic;

    constant CLK_PERIOD : time := 8 ns;  -- 125 MHz

begin

    ----------------------------------------------------------------------------
    -- DUT
    ----------------------------------------------------------------------------
    uut : entity work.rgmii_rx
        port map (
            rst           => rst,
            rgmii_rxc     => rgmii_rxc,
            rgmii_rxd     => rgmii_rxd,
            rgmii_rx_ctl  => rgmii_rx_ctl,
            rx_data_clk   => rx_data_clk,
            rx_data       => rx_data,
            rx_data_valid => rx_data_valid,
            rx_data_err   => open
        );

    ----------------------------------------------------------------------------
    -- Clock generation
    ----------------------------------------------------------------------------
    clk_gen : process
    begin
        rgmii_rxc <= '0';
        wait for CLK_PERIOD / 2;
        rgmii_rxc <= '1';
        wait for CLK_PERIOD / 2;
    end process clk_gen;

    ----------------------------------------------------------------------------
    -- Stimulus
    ----------------------------------------------------------------------------
    stim : process

        type byte_array_t is array (0 to 9) of std_logic_vector(7 downto 0);
        constant TEST_DATA : byte_array_t := (
            x"01", x"02", x"03", x"04", x"05",
            x"06", x"07", x"08", x"09", x"0A"
        );

    begin
        rst <= '1';
        wait for 100 ns;
        rst <= '0';
        wait for 20 ns;

        for i in 0 to 9 loop

            -- Rising edge: low nibble
            wait until rising_edge(rgmii_rxc);
            wait for 1 ns;
            rgmii_rxd    <= TEST_DATA(i)(3 downto 0);
            rgmii_rx_ctl <= '1';

            -- Falling edge: high nibble
            wait until falling_edge(rgmii_rxc);
            wait for 1 ns;
            rgmii_rxd    <= TEST_DATA(i)(7 downto 4);
            rgmii_rx_ctl <= '1';  -- (DV=1 xor ER=0) = 1

        end loop;

        -- Idle
        wait until rising_edge(rgmii_rxc);
        wait for 1 ns;
        rgmii_rxd    <= x"0";
        rgmii_rx_ctl <= '0';

        wait for 100 ns;
        report "rgmii_rx_tb complete";
        wait;
    end process stim;

end architecture sim;
