--------------------------------------------------------------------------------
-- uart_rx_tb
--
-- Drives a few UART frames into uart_rx and lets the simulator show that the
-- received bytes line up with the data sent. 100 MHz sysclk, 115200 baud
-- (BIT_PERIOD = 8680 ns).
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity uart_rx_tb is
end entity uart_rx_tb;

architecture sim of uart_rx_tb is

    signal clk           : std_logic                    := '0';
    signal rst           : std_logic                    := '1';
    signal uart_rx       : std_logic                    := '1';
    signal uart_rx_data  : std_logic_vector(7 downto 0) := (others => '0');
    signal uart_rx_valid : std_logic                    := '0';
    signal uart_rx_err   : std_logic                    := '0';

    constant CLK_PERIOD : time := 10 ns;
    constant BIT_PERIOD : time := 8680 ns;

begin

    ----------------------------------------------------------------------------
    -- DUT
    ----------------------------------------------------------------------------
    uut : entity work.uart_rx
        generic map (
            CLK_FREQ  => 100_000_000,
            BAUD_RATE => 115_200
        )
        port map (
            clk           => clk,
            rst           => rst,
            uart_rx       => uart_rx,
            uart_rx_data  => uart_rx_data,
            uart_rx_valid => uart_rx_valid,
            uart_rx_err   => uart_rx_err
        );

    clk <= not clk after CLK_PERIOD / 2;

    ----------------------------------------------------------------------------
    -- Stimulus
    ----------------------------------------------------------------------------
    stim : process

        procedure uart_send_byte (data_byte : in std_logic_vector(7 downto 0)) is
        begin
            -- Start bit
            uart_rx <= '0';
            wait for BIT_PERIOD;

            -- Data bits, LSB first
            for i in 0 to 7 loop
                uart_rx <= data_byte(i);
                wait for BIT_PERIOD;
            end loop;

            -- Stop bit
            uart_rx <= '1';
            wait for BIT_PERIOD;
        end procedure uart_send_byte;

    begin
        wait for 100 ns;
        rst <= '0';
        wait for 100 ns;

        uart_send_byte(x"AB");
        wait for 2 us;

        uart_send_byte(x"55");
        wait for 2 us;

        uart_send_byte(x"00");
        wait for 2 us;

        uart_send_byte(x"FF");

        report "All tests completed";
        wait;
    end process stim;

end architecture sim;
