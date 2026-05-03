--------------------------------------------------------------------------------
-- uart_to_rgmii_bridge_tb
--
-- Drives a small burst of bytes into the bridge over the UART-side interface
-- and lets the simulator show the FIFO fill, the idle-timeout trigger, and
-- the resulting RGMII TX nibbles. uart_clk = 100 MHz, rgmii_clk = 125 MHz.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_to_rgmii_bridge_tb is
end entity uart_to_rgmii_bridge_tb;

architecture sim of uart_to_rgmii_bridge_tb is

    signal rst        : std_logic := '1';
    signal uart_clk   : std_logic := '0';   -- 100 MHz
    signal rgmii_clk  : std_logic := '0';   -- 125 MHz

    signal uart_data  : std_logic_vector(7 downto 0) := (others => '0');
    signal uart_valid : std_logic                    := '0';

    signal rgmii_txd    : std_logic_vector(3 downto 0);
    signal rgmii_tx_ctl : std_logic;
    signal rgmii_txc    : std_logic;

    constant UART_PERIOD  : time := 10 ns;  -- 100 MHz
    constant RGMII_PERIOD : time := 8 ns;   -- 125 MHz

begin

    ----------------------------------------------------------------------------
    -- DUT
    ----------------------------------------------------------------------------
    uut : entity work.uart_to_rgmii_bridge
        port map (
            rst          => rst,
            uart_clk     => uart_clk,
            uart_data    => uart_data,
            uart_valid   => uart_valid,
            rgmii_clk    => rgmii_clk,
            rgmii_txd    => rgmii_txd,
            rgmii_tx_ctl => rgmii_tx_ctl,
            rgmii_txc    => rgmii_txc
        );

    ----------------------------------------------------------------------------
    -- Clock generation
    ----------------------------------------------------------------------------
    uart_clk_gen : process
    begin
        uart_clk <= '0';
        wait for UART_PERIOD / 2;
        uart_clk <= '1';
        wait for UART_PERIOD / 2;
    end process uart_clk_gen;

    rgmii_clk_gen : process
    begin
        rgmii_clk <= '0';
        wait for RGMII_PERIOD / 2;
        rgmii_clk <= '1';
        wait for RGMII_PERIOD / 2;
    end process rgmii_clk_gen;

    ----------------------------------------------------------------------------
    -- Stimulus
    ----------------------------------------------------------------------------
    stim : process

        procedure write_byte (data : in std_logic_vector(7 downto 0)) is
        begin
            uart_data  <= data;
            uart_valid <= '1';
            wait until rising_edge(uart_clk);
        end procedure write_byte;

    begin
        ------------------------------------------------------------------------
        -- Reset
        ------------------------------------------------------------------------
        rst <= '1';
        for i in 0 to 9 loop
            wait until rising_edge(uart_clk);
        end loop;
        rst <= '0';

        ------------------------------------------------------------------------
        -- Idle for a bit before first burst
        ------------------------------------------------------------------------
        for i in 0 to 9999 loop
            wait until rising_edge(uart_clk);
        end loop;

        ------------------------------------------------------------------------
        -- Burst 1: single byte, then a gap (exercises 1-byte timeout drain)
        ------------------------------------------------------------------------
        write_byte(x"12");
        uart_valid <= '0';
        for i in 0 to 10 loop
            wait until rising_edge(uart_clk);
        end loop;

        ------------------------------------------------------------------------
        -- Burst 2: four back-to-back bytes
        ------------------------------------------------------------------------
        write_byte(x"34");
        write_byte(x"56");
        write_byte(x"78");
        write_byte(x"9A");

        uart_valid <= '0';
        uart_data  <= x"00";
        wait until rising_edge(uart_clk);

        ------------------------------------------------------------------------
        -- Gap, then a single byte to retrigger the timeout
        ------------------------------------------------------------------------
        for i in 0 to 299 loop
            wait until rising_edge(uart_clk);
        end loop;

        write_byte(x"BC");
        uart_valid <= '0';
        uart_data  <= x"00";
        wait until rising_edge(uart_clk);

        report "Data write complete. Waiting for timeout trigger...";
        wait;
    end process stim;

end architecture sim;
