// Copyright 2018 Andrew Apted.
// This code is under the GNU General Public License, version 3
// or (at your option) any later version.

package main

import "fmt"
import "io"
import "os"

import "encoding/csv"
import "path/filepath"
import "strconv"
import "strings"

import "azul3d.org/engine/audio"
import "azul3d.org/engine/audio/wav"

// DMX_Audio_Save writes a lump of DMX audio data into a ".wav"
// file.
func DMX_Audio_Save(filename string, data []byte) error {
	f, err := os.Create(filename)
	if err != nil {
		return err
	}
	defer SafeClose(f, filename)

	rate := int(RawWord(data[2:]))

	if rate < 4000 {
		return fmt.Errorf("bad sample rate: %d", rate)
	}

	conf := audio.Config{SampleRate: rate, Channels: 1}

	encoder, err := wav.NewEncoder(f, conf)
	if err != nil {
		return err
	}

	sample := make(audio.Uint8, 1)

	length := int(RawLong(data[4:]))

	// double check the length
	// [ the first check was in IdentifySound ]
	if length > len(data)-8 {
		return fmt.Errorf("invalid sound lump")
	}

	// NOTE: we skip the 16 padding samples on each side

	// OPTIMIZE : write more than one sample at a time

	for i := 16; i < length-16; i++ {
		sample[0] = data[0x08+i]

		_, err = encoder.Write(sample)
		if err != nil {
			return err
		}
	}

	// don't write a file with no samples
	if length <= 32 {
		sample[0] = 0x80

		_, err = encoder.Write(sample)
		if err != nil {
			return err
		}
	}

	err = encoder.Close()
	return err
}

// DMX_Audio_Load reads a ".wav" file and converts it to a lump
// containing the DMX audio format.
func DMX_Audio_Load(filename string) ([]byte, error) {
	f, err := os.Open(filename)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	decoder, format, err := audio.NewDecoder(f)
	if err == audio.ErrFormat || format != "wav" {
		return nil, fmt.Errorf("file format is not WAV")
	}
	if err != nil {
		return nil, err
	}

	config := decoder.Config()
	rate := config.SampleRate

	if rate < 4000 || rate > 65535 {
		return nil, fmt.Errorf("bad sample rate: %d", rate)
	}

	// TODO : consider munging stereo files to mono (with a warning)
	if config.Channels != 1 {
		return nil, fmt.Errorf("file is stereo (%d channels)", config.Channels)
	}

	// pre-allocate room for the header *and* 16 padding samples
	data := make([]byte, 8+16, 10000)

	sample := make(audio.Uint8, 1)
	length := 0

	// OPTIMIZE : read more than one sample at a time

	for {
		n, err := decoder.Read(sample)
		if n > 0 {
			data = append(data, sample[0])
			length++
		}

		if err == audio.EOS {
			break
		}

		if err != nil {
			return nil, err
		}
	}

	// don't create an empty sound
	if length == 0 {
		sample[0] = 0x80
		data = append(data, sample[0])
		length++
	}

	// add the padding (16 bytes on each side)
	for k := 0; k < 16; k++ {
		data = append(data, sample[0])
		data[0x08+k] = data[0x08+16]
	}

	// update length for padding samples
	length += 32

	// fill in header
	data[0] = 3

	StoreWord(data[2:], uint16(rate))
	StoreLong(data[4:], uint32(length))

	return data, Ok
}

//----------------------------------------------------------------------

// PCSFX_Save converts a PC-Speaker sound lump into a ".csv" file.
// The output contains records with a single number: the tone for
// for each interval (1/140th of a second).
// Any writing error will be returned immediately.
func PCSFX_Save(filename string, data []byte) error {
	f, err := os.Create(filename)
	if err != nil {
		return err
	}
	defer SafeClose(f, filename)

	writer := csv.NewWriter(f)

	// RFC 4180 recommends using CR/LF line endings
	writer.UseCRLF = true

	// output a header line
	err = writer.Write([]string{"tone"})
	if err != nil {
		return err
	}

	// get length from the lump's 4-byte header
	if len(data) < 4 {
		return fmt.Errorf("pcsfx is too short")
	}

	length := int(RawWord(data[2:]))

	if length > len(data)-4 {
		return fmt.Errorf("pcsfx has bad length")
	}

	for i := 0; i < length; i++ {
		tone := data[4+i]

		record := make([]string, 1)
		record[0] = strconv.Itoa(int(tone))

		err = writer.Write(record)
		if err != nil {
			return err
		}
	}

	writer.Flush()

	return writer.Error()
}

// PCSFX_Load converts a ".csv" file back into a PC-Speaker sound
// lump.  Any reading or parsing error will be returned immediately.
func PCSFX_Load(filename string) ([]byte, error) {
	f, err := os.Open(filename)
	if err != nil {
		return nil, err
	}

	defer f.Close()

	// shorten filename for warnings
	filename = filepath.Base(filename)

	// pre-allocate a four-byte header.
	// the first two bytes should remain zero.
	// the next two bytes are the length, which is set below.
	data := make([]byte, 4, 1024)

	reader := csv.NewReader(f)

	reader.FieldsPerRecord = 1
	reader.TrimLeadingSpace = true

	// check the header
	header, err := reader.Read()
	if err == io.EOF {
		return nil, fmt.Errorf("file too short (missing header)")
	} else if err != nil {
		return nil, err
	}

	if strings.ToLower(header[0]) != "tone" {
		Warning("   %s: strange header", filename)
	}

	for {
		record, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, err
		}

		tone, err := strconv.Atoi(record[0])
		if err != nil || tone < 0 || tone > 96 {
			Warning("   %s: bad tone number '%d'", filename, tone)
			continue
		}

		data = append(data, byte(tone))
	}

	length := len(data) - 4

	// set the length field in the header
	StoreWord(data[2:], uint16(length))

	return data, Ok
}

//----------------------------------------------------------------------

// SNDCURVE_Save converts a SNDCURVE lump into a ".csv" file.
// The output contains records with two numbers: a sound volume
// between 1..127, and a length value (how many repetitions).
// Any writing error will be returned immediately.
func SNDCURVE_Save(filename string, data []byte) error {
	f, err := os.Create(filename)
	if err != nil {
		return err
	}
	defer SafeClose(f, filename)

	writer := csv.NewWriter(f)

	// RFC 4180 recommends using CR/LF line endings
	writer.UseCRLF = true

	// output a header line
	err = writer.Write([]string{"volume", "length"})
	if err != nil {
		return err
	}

	for len(data) > 0 {
		volume := data[0]
		length := 0

		for len(data) > 0 && data[0] == volume {
			data = data[1:]
			length++
		}

		record := make([]string, 2)
		record[0] = strconv.Itoa(int(volume))
		record[1] = strconv.Itoa(length)

		err = writer.Write(record)
		if err != nil {
			return err
		}
	}

	writer.Flush()

	return writer.Error()
}

// SNDCURVE_Load converts a ".csv" file back into a SNDCURVE lump.
// Any reading or parsing error will be returned immediately.
func SNDCURVE_Load(filename string) ([]byte, error) {
	f, err := os.Open(filename)
	if err != nil {
		return nil, err
	}

	defer f.Close()

	// shorten filename for warnings
	filename = filepath.Base(filename)

	data := make([]byte, 0, 8192)

	reader := csv.NewReader(f)

	reader.FieldsPerRecord = 2
	reader.TrimLeadingSpace = true

	// check the header
	header, err := reader.Read()
	if err == io.EOF {
		return nil, fmt.Errorf("file too short (missing header)")
	} else if err != nil {
		return nil, err
	}

	if strings.ToLower(header[0]) != "volume" ||
		strings.ToLower(header[1]) != "length" {

		Warning("   %s: strange header", filename)
	}

	for {
		record, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, err
		}

		volume, err := strconv.Atoi(record[0])
		if err != nil || volume < 0 || volume > 127 {
			Warning("   %s: bad volume '%d'", filename, volume)
			continue
		}

		length, err := strconv.Atoi(record[1])
		if err != nil || length < 0 || length > 9999 {
			Warning("   %s: bad length '%d'", filename, volume)
			continue
		}

		for i := 0; i < length; i++ {
			data = append(data, byte(volume))
		}
	}

	return data, Ok
}
