--------------------------------------------------------------------------------
-- eth_crc32
--
-- Ethernet CRC-32 generator (auto-framed). Computes the IEEE 802.3 FCS over a
-- stream of input bytes. Packet boundaries are detected automatically from
-- data_valid:
--
--   * rising edge of data_valid  -> start of packet (CRC reloaded to 0xFFFFFFFF)
--   * falling edge of data_valid -> end of packet (final FCS latched on crc_out)
--
-- Polynomial : 0x04C11DB7 (CRC-32/IEEE 802.3)
-- Initial    : 0xFFFFFFFF
-- Reflect in : yes (LSB-first bit order, as transmitted on the wire)
-- Reflect out: yes
-- XOR out    : 0xFFFFFFFF
--
-- Notes / assumptions:
--   * data_valid must remain continuously high for every byte of a packet.
--     If data_valid can gap mid-packet (e.g. back-pressure from a streaming
--     bus), this auto-framing scheme will incorrectly terminate the packet.
--   * crc_out / crc_valid become valid one cycle AFTER the falling edge of
--     data_valid (the falling edge is what tells us the previously latched
--     byte was the last one).
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity eth_crc32 is
    port (
        clk        : in  std_logic;
        rst        : in  std_logic;                     -- synchronous, active high
        data_in    : in  std_logic_vector(7 downto 0);  -- input byte (LSB first on wire)
        data_valid : in  std_logic;                     -- high for every valid byte
        crc_out    : out std_logic_vector(31 downto 0); -- final 32-bit FCS
        crc_valid  : out std_logic                      -- pulses high when crc_out valid
    );
end entity eth_crc32;

architecture rtl of eth_crc32 is

    -- Running CRC register (non-reflected form internally)
    signal crc_reg : std_logic_vector(31 downto 0) := (others => '1');

    -- Edge detection: remember data_valid from the previous cycle
    signal data_valid_d1 : std_logic := '0';

    -- Derived single-cycle pulses
    signal start_pkt : std_logic;  -- rising edge of data_valid
    signal end_pkt   : std_logic;  -- falling edge of data_valid

    -- Registered outputs
    signal crc_out_reg   : std_logic_vector(31 downto 0) := (others => '0');
    signal crc_valid_reg : std_logic := '0';

    ----------------------------------------------------------------------------
    -- next_crc
    --
    -- Computes the next CRC-32 state given the current state and one input
    -- byte. This is the unrolled equivalent of clocking the LFSR 8 times with
    -- polynomial 0x04C11DB7, with the input byte bit-reflected before being
    -- fed in (which is equivalent to processing bits LSB-first as they arrive
    -- on the Ethernet wire).
    ----------------------------------------------------------------------------
    function next_crc (crc_in : std_logic_vector(31 downto 0);
                       data   : std_logic_vector(7  downto 0))
        return std_logic_vector
    is
        variable c : std_logic_vector(31 downto 0);
        variable d : std_logic_vector(7  downto 0);
        variable n : std_logic_vector(31 downto 0);
    begin
        c := crc_in;
        -- Reflect input byte: bit 0 of the wire -> MSB of byte
        for i in 0 to 7 loop
            d(i) := data(7 - i);
        end loop;

        n(0)  := c(24) xor c(30) xor d(1) xor d(7);
        n(1)  := c(24) xor c(25) xor c(30) xor c(31) xor d(0) xor d(1) xor d(6) xor d(7);
        n(2)  := c(24) xor c(25) xor c(26) xor c(30) xor c(31) xor d(0) xor d(1) xor d(5) xor d(6) xor d(7);
        n(3)  := c(25) xor c(26) xor c(27) xor c(31) xor d(0) xor d(4) xor d(5) xor d(6);
        n(4)  := c(24) xor c(26) xor c(27) xor c(28) xor c(30) xor d(1) xor d(3) xor d(4) xor d(5) xor d(7);
        n(5)  := c(24) xor c(25) xor c(27) xor c(28) xor c(29) xor c(30) xor c(31)
                 xor d(0) xor d(1) xor d(2) xor d(3) xor d(4) xor d(6) xor d(7);
        n(6)  := c(25) xor c(26) xor c(28) xor c(29) xor c(30) xor c(31)
                 xor d(0) xor d(1) xor d(2) xor d(3) xor d(5) xor d(6);
        n(7)  := c(24) xor c(26) xor c(27) xor c(29) xor c(31) xor d(0) xor d(2) xor d(4) xor d(5) xor d(7);
        n(8)  := c(0)  xor c(24) xor c(25) xor c(27) xor c(28) xor d(3) xor d(4) xor d(6) xor d(7);
        n(9)  := c(1)  xor c(25) xor c(26) xor c(28) xor c(29) xor d(2) xor d(3) xor d(5) xor d(6);
        n(10) := c(2)  xor c(24) xor c(26) xor c(27) xor c(29) xor d(2) xor d(4) xor d(5) xor d(7);
        n(11) := c(3)  xor c(24) xor c(25) xor c(27) xor c(28) xor d(3) xor d(4) xor d(6) xor d(7);
        n(12) := c(4)  xor c(24) xor c(25) xor c(26) xor c(28) xor c(29) xor c(30)
                 xor d(1) xor d(2) xor d(3) xor d(5) xor d(6) xor d(7);
        n(13) := c(5)  xor c(25) xor c(26) xor c(27) xor c(29) xor c(30) xor c(31)
                 xor d(0) xor d(1) xor d(2) xor d(4) xor d(5) xor d(6);
        n(14) := c(6)  xor c(26) xor c(27) xor c(28) xor c(30) xor c(31)
                 xor d(0) xor d(1) xor d(3) xor d(4) xor d(5);
        n(15) := c(7)  xor c(27) xor c(28) xor c(29) xor c(31) xor d(0) xor d(2) xor d(3) xor d(4);
        n(16) := c(8)  xor c(24) xor c(28) xor c(29) xor d(2) xor d(3) xor d(7);
        n(17) := c(9)  xor c(25) xor c(29) xor c(30) xor d(1) xor d(2) xor d(6);
        n(18) := c(10) xor c(26) xor c(30) xor c(31) xor d(0) xor d(1) xor d(5);
        n(19) := c(11) xor c(27) xor c(31) xor d(0) xor d(4);
        n(20) := c(12) xor c(28) xor d(3);
        n(21) := c(13) xor c(29) xor d(2);
        n(22) := c(14) xor c(24) xor d(7);
        n(23) := c(15) xor c(24) xor c(25) xor c(30) xor d(1) xor d(6) xor d(7);
        n(24) := c(16) xor c(25) xor c(26) xor c(31) xor d(0) xor d(5) xor d(6);
        n(25) := c(17) xor c(26) xor c(27) xor d(4) xor d(5);
        n(26) := c(18) xor c(24) xor c(27) xor c(28) xor c(30) xor d(1) xor d(3) xor d(4) xor d(7);
        n(27) := c(19) xor c(25) xor c(28) xor c(29) xor c(31) xor d(0) xor d(2) xor d(3) xor d(6);
        n(28) := c(20) xor c(26) xor c(29) xor c(30) xor d(1) xor d(2) xor d(5);
        n(29) := c(21) xor c(27) xor c(30) xor c(31) xor d(0) xor d(1) xor d(4);
        n(30) := c(22) xor c(28) xor c(31) xor d(0) xor d(3);
        n(31) := c(23) xor c(29) xor d(2);

        return n;
    end function next_crc;

    ----------------------------------------------------------------------------
    -- finalize_crc
    --
    -- Reflect the 32-bit CRC register and XOR with 0xFFFFFFFF to produce the
    -- final FCS value in the form transmitted on the Ethernet wire.
    ----------------------------------------------------------------------------
    function finalize_crc (crc_in : std_logic_vector(31 downto 0))
        return std_logic_vector
    is
        variable r : std_logic_vector(31 downto 0);
    begin
        for i in 0 to 31 loop
            r(i) := crc_in(31 - i);
        end loop;
        return r xor x"FFFFFFFF";
    end function finalize_crc;

begin

    ----------------------------------------------------------------------------
    -- Edge-detected packet boundaries
    ----------------------------------------------------------------------------
    start_pkt <= data_valid and not data_valid_d1;
    end_pkt   <= data_valid_d1 and not data_valid;

    ----------------------------------------------------------------------------
    -- crc_update
    --
    -- One byte per clock when data_valid is high. On packet boundary, reload
    -- 0xFFFFFFFF and consume the first byte in the same cycle. On the falling
    -- edge of data_valid, the register already holds the post-last-byte CRC,
    -- so finalize and present it.
    ----------------------------------------------------------------------------
    crc_update : process (clk)
    begin
        if rising_edge(clk) then
            crc_valid_reg <= '0';
            data_valid_d1 <= data_valid;

            if rst = '1' then
                crc_reg       <= (others => '1');
                crc_out_reg   <= (others => '0');
                crc_valid_reg <= '0';
                data_valid_d1 <= '0';
            else
                if data_valid = '1' then
                    if start_pkt = '1' then
                        crc_reg <= next_crc(x"FFFFFFFF", data_in);
                    else
                        crc_reg <= next_crc(crc_reg, data_in);
                    end if;
                end if;

                if end_pkt = '1' then
                    crc_out_reg   <= finalize_crc(crc_reg);
                    crc_valid_reg <= '1';
                end if;
            end if;
        end if;
    end process crc_update;

    crc_out   <= crc_out_reg;
    crc_valid <= crc_valid_reg;

end architecture rtl;
