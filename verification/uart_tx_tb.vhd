--------------------------------------------------------------------------------
-- uart_tx_tb
--
-- Pulses uart_tx_start with a few different bytes and waits for uart_tx_busy
-- to clear after each, letting the simulator show the serial frame on
-- uart_tx. 100 MHz sysclk, 115200 baud (BIT_PERIOD = 8680 ns).
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity uart_tx_tb is
end entity uart_tx_tb;

architecture sim of uart_tx_tb is

    signal clk           : std_logic                    := '0';
    signal rst           : std_logic                    := '1';
    signal uart_tx_data  : std_logic_vector(7 downto 0) := (others => '0');
    signal uart_tx_start : std_logic                    := '0';
    signal uart_tx       : std_logic;
    signal uart_tx_busy  : std_logic;

    constant CLK_PERIOD : time := 10 ns;
    constant BIT_PERIOD : time := 8680 ns;

begin

    ----------------------------------------------------------------------------
    -- DUT
    ----------------------------------------------------------------------------
    uut : entity work.uart_tx
        generic map (
            CLK_FREQ  => 100_000_000,
            BAUD_RATE => 115_200
        )
        port map (
            clk           => clk,
            rst           => rst,
            uart_tx_data  => uart_tx_data,
            uart_tx_start => uart_tx_start,
            uart_tx       => uart_tx,
            uart_tx_busy  => uart_tx_busy
        );

    clk <= not clk after CLK_PERIOD / 2;

    ----------------------------------------------------------------------------
    -- Stimulus
    ----------------------------------------------------------------------------
    stim : process

        procedure uart_send (data : in std_logic_vector(7 downto 0)) is
        begin
            wait until falling_edge(clk);
            uart_tx_data  <= data;
            uart_tx_start <= '1';
            wait until falling_edge(clk);
            uart_tx_start <= '0';
            wait until uart_tx_busy = '0';
            wait for 2 us;
        end procedure uart_send;

    begin
        wait for 100 ns;
        rst <= '0';
        wait for 100 ns;

        uart_send(x"55");
        uart_send(x"AA");
        uart_send(x"12");
        uart_send(x"34");

        report "Test complete";
        wait;
    end process stim;

end architecture sim;
