--------------------------------------------------------------------------------
-- uart_tx
--
-- 8-N-1 UART transmitter. On a one-cycle uart_tx_start pulse with uart_tx_busy
-- low, latches uart_tx_data and shifts it out on uart_tx as start + 8 data
-- (LSB first) + stop. uart_tx_busy stays high for the full frame.
--
-- Generics:
--   CLK_FREQ   - input clock frequency in Hz
--   BAUD_RATE  - line baud rate
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_tx is
    generic (
        CLK_FREQ  : integer := 100_000_000;
        BAUD_RATE : integer := 115_200
    );
    port (
        clk           : in  std_logic;
        rst           : in  std_logic;
        uart_tx_data  : in  std_logic_vector(7 downto 0);
        uart_tx_start : in  std_logic;
        uart_tx       : out std_logic;
        uart_tx_busy  : out std_logic
    );
end entity uart_tx;

architecture rtl of uart_tx is

    constant CLKS_PER_BIT : integer := CLK_FREQ / BAUD_RATE;

    -- Frame layout in shift_reg: { stop , data[7:0] , start } (shifted out LSB first)
    signal shift_reg     : std_logic_vector(9 downto 0);
    signal clk_count_reg : unsigned(31 downto 0);
    signal bit_count_reg : unsigned(3 downto 0);
    signal tx_line_reg   : std_logic := '1';
    signal tx_busy_reg   : std_logic := '0';

begin

    ----------------------------------------------------------------------------
    -- tx_fsm
    --
    -- Idle holds the line high. On uart_tx_start, frame is loaded and shifted
    -- out one bit per CLKS_PER_BIT cycles for 10 bits, then returns to idle.
    ----------------------------------------------------------------------------
    tx_fsm : process (clk, rst)
    begin
        if rst = '1' then
            shift_reg     <= (others => '1');
            clk_count_reg <= (others => '0');
            bit_count_reg <= (others => '0');
            tx_line_reg   <= '1';
            tx_busy_reg   <= '0';

        elsif rising_edge(clk) then

            if tx_busy_reg = '0' then
                -- IDLE
                tx_line_reg <= '1';

                if uart_tx_start = '1' then
                    -- Load: stop(1) | data | start(0)
                    shift_reg     <= '1' & uart_tx_data & '0';
                    bit_count_reg <= (others => '0');
                    clk_count_reg <= (others => '0');
                    tx_busy_reg   <= '1';
                end if;

            else
                -- BUSY: shift out LSB-first, one bit per CLKS_PER_BIT
                tx_line_reg <= shift_reg(0);

                if clk_count_reg = CLKS_PER_BIT - 1 then
                    clk_count_reg <= (others => '0');
                    shift_reg     <= '1' & shift_reg(9 downto 1);

                    if bit_count_reg = 9 then
                        tx_busy_reg <= '0';
                    else
                        bit_count_reg <= bit_count_reg + 1;
                    end if;
                else
                    clk_count_reg <= clk_count_reg + 1;
                end if;

            end if;

        end if;
    end process tx_fsm;

    uart_tx      <= tx_line_reg;
    uart_tx_busy <= tx_busy_reg;

end architecture rtl;
