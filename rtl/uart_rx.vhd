--------------------------------------------------------------------------------
-- uart_rx
--
-- 8-N-1 UART receiver. Samples uart_rx in the middle of each bit period and
-- drives the assembled byte out on uart_rx_data with a one-cycle uart_rx_valid
-- pulse. Framing errors (stop bit not high) pulse uart_rx_err for one cycle
-- and the byte is discarded.
--
-- Generics:
--   CLK_FREQ   - input clock frequency in Hz
--   BAUD_RATE  - line baud rate
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_rx is
    generic (
        CLK_FREQ  : integer := 100_000_000;
        BAUD_RATE : integer := 115_200
    );
    port (
        clk           : in  std_logic;
        rst           : in  std_logic;
        uart_rx       : in  std_logic;
        uart_rx_data  : out std_logic_vector(7 downto 0);
        uart_rx_valid : out std_logic;
        uart_rx_err   : out std_logic
    );
end entity uart_rx;

architecture rtl of uart_rx is

    constant CLKS_PER_BIT : integer := CLK_FREQ / BAUD_RATE;

    type state_t is (
        IDLE,
        START_BIT,
        DATA_BITS,
        STOP_BIT
    );

    signal state_reg     : state_t;
    signal bit_index_reg : unsigned(3 downto 0);
    signal clk_count_reg : unsigned(15 downto 0);
    signal rx_err_reg    : std_logic;
    signal rx_data_sr    : std_logic_vector(7 downto 0);

begin

    ----------------------------------------------------------------------------
    -- rx_fsm
    --
    -- Bit-period FSM: detects start bit, samples 8 data bits LSB-first, checks
    -- stop bit. Outputs are registered.
    ----------------------------------------------------------------------------
    rx_fsm : process (clk, rst)
    begin
        if rst = '1' then
            state_reg     <= IDLE;
            bit_index_reg <= (others => '0');
            clk_count_reg <= (others => '0');
            rx_data_sr    <= (others => '0');
            uart_rx_data  <= (others => '0');
            uart_rx_valid <= '0';
            rx_err_reg    <= '0';
        elsif rising_edge(clk) then

            rx_err_reg <= '0';

            case state_reg is

                when IDLE =>
                    bit_index_reg <= (others => '0');
                    clk_count_reg <= (others => '0');
                    uart_rx_valid <= '0';
                    if uart_rx = '0' then
                        state_reg <= START_BIT;
                    end if;

                when START_BIT =>
                    if clk_count_reg = (CLKS_PER_BIT / 2) - 1 then
                        if uart_rx = '0' then
                            clk_count_reg <= (others => '0');
                            state_reg     <= DATA_BITS;
                        else
                            state_reg <= IDLE;
                        end if;
                    else
                        clk_count_reg <= clk_count_reg + 1;
                    end if;

                when DATA_BITS =>
                    if clk_count_reg = CLKS_PER_BIT - 1 then
                        rx_data_sr    <= uart_rx & rx_data_sr(7 downto 1);
                        clk_count_reg <= (others => '0');

                        if bit_index_reg = 7 then
                            state_reg     <= STOP_BIT;
                            bit_index_reg <= (others => '0');
                        else
                            bit_index_reg <= bit_index_reg + 1;
                        end if;
                    else
                        clk_count_reg <= clk_count_reg + 1;
                    end if;

                when STOP_BIT =>
                    if clk_count_reg = CLKS_PER_BIT - 1 then
                        if uart_rx = '1' then
                            uart_rx_valid <= '1';
                            uart_rx_data  <= rx_data_sr;
                        else
                            rx_err_reg <= '1';
                        end if;
                        state_reg <= IDLE;
                    else
                        clk_count_reg <= clk_count_reg + 1;
                    end if;

                when others =>
                    state_reg <= IDLE;
            end case;
        end if;
    end process rx_fsm;

    uart_rx_err <= rx_err_reg;

end architecture rtl;
