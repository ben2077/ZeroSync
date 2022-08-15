# Serialization Library
# Functions for reading and writing byte buffers
# The stream is represented as an array of 32-bit unsigned integers
# 
# See also:
# - https://github.com/mimblewimble/grin/blob/master/core/src/ser.rs
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.pow import pow
from starkware.cairo.common.math import unsigned_div_rem

# The base for byte-wise shifts via multiplication and integer division
const BYTE = 2**8

# The size of an Uint32 is 4 bytes
const UINT32_SIZE = 4

struct Reader: 
    member head : felt*
    member offset : felt
    member payload : felt
end

func init_reader(array: felt*) -> (reader : Reader):
    return (Reader(array, 1, 0))
end 

func read_uint8{reader: Reader, range_check_ptr}() -> (byte: felt):
    if reader.offset == 1:
        # The Reader is empty, so we read from the head, return the first byte,
        # and copy the remaining three bytes into the Reader's payload.
        let (byte, payload) = unsigned_div_rem([reader.head], BYTE**3)
        let reader = Reader(reader.head + 1, UINT32_SIZE, payload * BYTE)
        return (byte)
    else: 
        # The Reader is not empty. So we read the first byte from its payload
        # and continue with the remaining bytes.
        let (byte, payload) = unsigned_div_rem(reader.payload, BYTE**3)
        let reader = Reader(reader.head, reader.offset - 1, payload * BYTE)
        return (byte)
    end
end

func _read_n_bytes_into_felt{reader: Reader, range_check_ptr}(
    output: felt*, value, base, loop_counter):
    if loop_counter == 0:
        assert [output] = value
        return ()
    end
    let (byte) = read_uint8()
    _read_n_bytes_into_felt(output, byte * base + value, base * BYTE, loop_counter - 1)
    return ()
end 

func read_uint16{reader: Reader, range_check_ptr}() -> (result: felt):
    alloc_locals
    let (result) = alloc()
    _read_n_bytes_into_felt(result, 0, 1, 2)
    return ([result]) 
end 

func read_uint32{reader: Reader, range_check_ptr}() -> (result: felt):
    alloc_locals
    let (result) = alloc()
    _read_n_bytes_into_felt(result, 0, 1, 4)
    return ([result]) 
end 

func read_uint64{reader: Reader, range_check_ptr}() -> (result: felt):
    alloc_locals
    let (result) = alloc()
    _read_n_bytes_into_felt(result, 0, 1, 8)
    return ([result])
end

# Reads a VarInt from the buffer
# 
# See also:
# - https://developer.bitcoin.org/reference/transactions.html#compactsize-unsigned-integers
func read_varint{reader: Reader, range_check_ptr}() -> (result: felt):
    # Read the first byte 
    let (first_byte) = read_uint8()

    # Now check how many more bytes we have to read
    
    if first_byte == 0xff:
        # This varint has 8 more bytes
        let (uint64) = read_uint64()
        return (uint64)
    end

    if first_byte == 0xfe:
        # This varint has 4 more bytes
        let (uint32) = read_uint32()
        return (uint32)
    end

    if first_byte == 0xfd:
        # This varint has 2 more bytes
        let (uint16) = read_uint16()
        return (uint16)
    end
    
    # This varint is only 1 byte
    return (first_byte)
end

func _read_into_uint32_array{reader: Reader, range_check_ptr}(
    output: felt*, loop_counter):
    if loop_counter == 0:
        return ()
    end
    _read_n_bytes_into_felt(output, 0, 1, UINT32_SIZE)
    _read_into_uint32_array(output + 1, loop_counter - 1)
    return ()
end


func read_bytes{reader: Reader, range_check_ptr}(
    length:felt) -> (result: felt*):
    alloc_locals

    let (result) = alloc()
    let (len_div_4, len_mod_4) = unsigned_div_rem(length, UINT32_SIZE)
    # Read as many 4-byte chunks as possible into the array 
    _read_into_uint32_array(result, len_div_4)
    # Read up to three more bytes
    _read_n_bytes_into_felt(result + len_div_4, 0, 1, len_mod_4)
    return (result)
end

func read_bytes_endian{reader: Reader, range_check_ptr}(
    length:felt) -> (result: felt*):
    alloc_locals

    let (result) = alloc()
    let (len_div_4, len_mod_4) = unsigned_div_rem(length, UINT32_SIZE)
    _read_into_uint32_array_endian(result, len_div_4)
    _read_n_bytes_into_felt_endian(result + len_div_4, 0, len_mod_4)
    return (result)
end

func _read_into_uint32_array_endian{reader: Reader, range_check_ptr}(
    output: felt*, loop_counter):
    if loop_counter == 0:
        return ()
    end
    _read_n_bytes_into_felt_endian(output, 0, UINT32_SIZE)
    _read_into_uint32_array_endian(output + 1, loop_counter - 1)
    return ()
end

func _read_n_bytes_into_felt_endian{reader: Reader, range_check_ptr}(
    output: felt*, value, loop_counter):
    if loop_counter == 0:
        assert [output] = value
        return ()
    end
    let (byte) = read_uint8()
    _read_n_bytes_into_felt_endian(output, value * BYTE + byte, loop_counter - 1)
    return ()
end

func read_uint32_endian{reader: Reader, range_check_ptr}() -> (result: felt):
    alloc_locals
    let (result) = alloc()
    _read_n_bytes_into_felt_endian(result, 0, UINT32_SIZE)
    return ([result])
end

func read_hash{reader: Reader, range_check_ptr}() -> (result: felt*):
    return read_bytes_endian(32)
end

struct Writer:
    member head : felt*
    member offset : felt
    member payload : felt 
end

func init_writer(array: felt*) -> (writer : Writer):
    return (Writer(array, 0, 0))
end 

# Any unwritten data in the writer's temporary memory is written to the writer.
func flush_writer{range_check_ptr}(writer: Writer): 
    # Write what's left in our writer 
    # Then fill up the uint32 with trailing zeros
    let (base) = pow(BYTE, UINT32_SIZE - writer.offset)
    assert [writer.head] = writer.payload * base
    return ()
end

func write_uint8{writer: Writer}(source):
    alloc_locals
    
    let value =  writer.payload * BYTE + source
    
    let offset = writer.offset + 1
    if offset == UINT32_SIZE:
        assert [writer.head] = value
        tempvar writer = Writer(writer.head + 1, 0, 0)
    else: 
        tempvar writer = Writer(writer.head, offset, value)
    end
    return ()
end

func write_uint16{writer: Writer, range_check_ptr}(source):
    alloc_locals
    let (uint8_1, uint8_0) = unsigned_div_rem(source, BYTE)
    write_uint8(uint8_0)
    write_uint8(uint8_1)
    return ()
end

func write_uint32{writer: Writer, range_check_ptr}(source):
    alloc_locals
    let (uint24,  uint8_0) = unsigned_div_rem(source, BYTE)
    let (uint16,  uint8_1) = unsigned_div_rem(uint24, BYTE)
    let (uint8_3, uint8_2) = unsigned_div_rem(uint16, BYTE)
    write_uint8(uint8_0)
    write_uint8(uint8_1)
    write_uint8(uint8_2)
    write_uint8(uint8_3)
    return ()
end

func write_uint64{writer: Writer, range_check_ptr}(source: felt):
    # TODO: implement me
    assert 1=2
    return()
end 

func write_varint{writer: Writer, range_check_ptr}(source: felt):
    # TODO: implement me
    assert 1=2
    return ()
end 

func write_uint32_endian{writer: Writer, range_check_ptr}(source):
    alloc_locals
    let (uint24,  uint8_3) = unsigned_div_rem(source, BYTE)
    let (uint16,  uint8_2) = unsigned_div_rem(uint24, BYTE)
    let (uint8_0, uint8_1) = unsigned_div_rem(uint16, BYTE)
    write_uint8(uint8_0)
    write_uint8(uint8_1)
    write_uint8(uint8_2)
    write_uint8(uint8_3)
    return ()
end

func write_hash{writer: Writer, range_check_ptr}(source: felt*):
    write_uint32_endian(source[0])
    write_uint32_endian(source[1])
    write_uint32_endian(source[2])
    write_uint32_endian(source[3])
    write_uint32_endian(source[4])
    write_uint32_endian(source[5])
    write_uint32_endian(source[6])
    write_uint32_endian(source[7])
    return ()
end