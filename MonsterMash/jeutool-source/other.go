// Copyright 2018 Andrew Apted.
// This code is under the GNU General Public License, version 3
// or (at your option) any later version.

package main

import "os"
import "io"
import "fmt"

import "bufio"
import "bytes"
import "strings"
import "path/filepath"

// TXT_Load reads a plain text file into memory.
// If the line endings contain CR (carriage return) then
// they are removed.  NUL bytes are also removed.
// The file may begin with a unicode BOM (byte-order mark),
// in which case that is also removed.
func TXT_Load(filename string) ([]byte, error) {
	f, err := os.Open(filename)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	bf := bufio.NewReader(f)

	data := make([]byte, 0, 1024)

	for {
		ch, err := bf.ReadByte()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, err
		}

		if ch == 0 || ch == '\r' {
			continue
		}

		data = append(data, ch)
	}

	// remove a Unicode BOM (byte-order mark)
	if len(data) >= 3 &&
		data[0] == 0xEF &&
		data[1] == 0xBB &&
		data[2] == 0xBF {

		data = data[3:]
	}

	return data, Ok
}

// TXT_Save writes a plain text file from a buffer.
// Any NUL or CR (carriage return) in the buffer is ignored.
// For Unix-like systems, line endings will simply consist of
// a LF (line-feed) character, whereas on Windows each LF in
// but buffer will be written as a CR/LF pair.
func TXT_Save(filename string, data []byte) error {
	f, err := os.Create(filename)
	if err != nil {
		return err
	}
	defer SafeClose(f, filename)

	bf := bufio.NewWriter(f)

	is_windows := (os.PathSeparator == '\\')

	for _, ch := range data {
		if ch == 0 || ch == '\r' {
			continue
		}

		if ch == '\n' && is_windows {
			err := bf.WriteByte('\r')
			if err != nil {
				return err
			}
		}

		err := bf.WriteByte(ch)
		if err != nil {
			return err
		}
	}

	return bf.Flush()
}

//----------------------------------------------------------------------

func SWITCHES_Load(filename string) ([]byte, error) {
	text, err := TXT_Load(filename)
	if err != nil {
		return nil, err
	}

	// simplify filename for warning messages
	filename = filepath.Base(filename)

	var data bytes.Buffer
	var line string

	for {
		text, line = SWAN_ParseLine(text)
		if text == nil {
			break
		}

		// skip blank lines and comments
		if line == "" {
			continue
		}

		line = strings.ToUpper(line)

		// ignore the usual marker
		if line == "[SWITCHES]" {
			continue
		}

		if line[0] == '[' {
			Warning("   %s: invalid section: %s", filename, line)
			continue
		}

		// parse a valid line

		var epi byte
		var tex1, tex2 string

		n, _ := fmt.Sscanf(line, "%d %s %s", &epi, &tex1, &tex2)
		if n != 3 {
			Warning("   %s: cannot parse line: %s", filename, line)
			continue
		}

		if len(tex1) > 8 {
			Warning("   %s: texture name too long: %s", filename, tex1)
			continue
		}
		if len(tex2) > 8 {
			Warning("   %s: texture name too long: %s", filename, tex2)
			continue
		}

		// create the record
		SWAN_AddString(&data, tex1)
		SWAN_AddString(&data, tex2)

		data.WriteByte(epi)
		data.WriteByte(0)

	}

	// add termination record (all zeros)
	for pad := 0; pad < 20; pad++ {
		data.WriteByte(0)
	}

	return data.Bytes(), Ok
}

func SWITCHES_Save(filename string, data []byte) error {
	var text bytes.Buffer

	// write the section header
	text.WriteString("[SWITCHES]\n")
	text.WriteString("#epi  texture1   texture2\n")
	text.WriteString("#------------------------\n")

	count := len(data) / 20

	for i := 0; i < count; i++ {
		record := data[i*20 : (i+1)*20]

		epi := int(record[18])

		// termination record?
		if epi == 0 {
			break
		}

		tex1 := RawString(record[0:8])
		tex2 := RawString(record[9:17])

		// prevent empty texture names
		if tex1 == "" {
			Warning("   SWITCHES lump contains invalid texture name")
			tex1 = "_"
		}
		if tex2 == "" {
			Warning("   SWITCHES lump contains invalid texture name")
			tex2 = "_"
		}

		fmt.Fprintf(&text, "%-4d  %-9s  %-9s\n", epi, tex1, tex2)
	}

	return TXT_Save(filename, text.Bytes())
}

func ANIMATED_Load(filename string) ([]byte, error) {
	text, err := TXT_Load(filename)
	if err != nil {
		return nil, err
	}

	// simplify filename for warning messages
	filename = filepath.Base(filename)

	var data bytes.Buffer

	var mode byte = 99
	var line string

	for {
		text, line = SWAN_ParseLine(text)
		if text == nil {
			break
		}

		// skip blank lines and comments
		if line == "" {
			continue
		}

		line = strings.ToUpper(line)

		if line == "[TEXTURES]" {
			mode = 1
			continue
		}
		if line == "[FLATS]" {
			mode = 0
			continue
		}

		if line[0] == '[' {
			Warning("   %s: invalid section: %s", filename, line)
			continue
		}

		// handle texture lines outside of any section
		if mode > 1 {
			if mode != 100 {
				Warning("   %s: missing section marker", filename)
				mode = 100
			}
			continue
		}

		// parse a valid line

		var speed byte
		var tex1, tex2 string

		n, _ := fmt.Sscanf(line, "%d %s %s", &speed, &tex1, &tex2)
		if n != 3 {
			Warning("   %s: cannot parse line: %s", filename, line)
			continue
		}

		if len(tex1) > 8 {
			Warning("   %s: texture name too long: %s", filename, tex1)
			continue
		}
		if len(tex2) > 8 {
			Warning("   %s: texture name too long: %s", filename, tex2)
			continue
		}

		// create the record
		data.WriteByte(mode)

		SWAN_AddString(&data, tex1)
		SWAN_AddString(&data, tex2)

		data.WriteByte(speed)
		data.WriteByte(0)
		data.WriteByte(0)
		data.WriteByte(0)
	}

	// add termination record (-1 in first byte).
	//
	// NOTE: the SWANTBLS program writes a partial record here,
	//       however a whole record should be OK.
	data.WriteByte(0xFF)

	for pad := 1; pad < 23; pad++ {
		data.WriteByte(0)
	}

	return data.Bytes(), Ok
}

func ANIMATED_Save(filename string, data []byte) error {
	var text bytes.Buffer

	count := len(data) / 23

	var mode byte

	for mode = 0; mode < 2; mode++ {
		// write the section header
		if mode == 0 {
			text.WriteString("[FLATS]\n")
		} else {
			text.WriteString("[TEXTURES]\n")
		}

		text.WriteString("#speed  last       first   \n")
		text.WriteString("#--------------------------\n")

		for i := 0; i < count; i++ {
			record := data[i*23 : (i+1)*23]

			// termination record?
			if record[0] == 0xFF {
				break
			}

			if record[0] != mode {
				continue
			}

			tex1 := RawString(record[1:9])
			tex2 := RawString(record[10:18])

			speed := int(record[19])

			// prevent empty texture names
			if tex1 == "" {
				Warning("   ANIMATED lump contains invalid texture name")
				tex1 = "_"
			}
			if tex2 == "" {
				Warning("   ANIMATED lump contains invalid texture name")
				tex2 = "_"
			}

			fmt.Fprintf(&text, "%-6d  %-9s  %-9s\n", speed, tex1, tex2)
		}

		text.WriteString("\n")
	}

	return TXT_Save(filename, text.Bytes())
}

func SWAN_ParseLine(text []byte) ([]byte, string) {
	// reached the end of the buffer?
	if len(text) == 0 {
		return nil, "EOF"
	}

	var sb strings.Builder

	in_comment := false

	for len(text) > 0 {
		ch := text[0]
		text = text[1:]

		// ignore any ^Z (break) character
		if ch == '\x1A' {
			continue
		}

		// end of line?
		if ch == '\n' {
			break
		}

		// comment?
		if ch == '#' || ch == ';' {
			in_comment = true
		}

		if !in_comment {
			sb.WriteByte(ch)
		}
	}

	line := strings.TrimSpace(sb.String())

	return text, line
}

func SWAN_AddString(data *bytes.Buffer, s string) {
	if len(s) > 8 {
		s = s[0:8]
	}

	data.WriteString(s)

	for i := len(s); i < 9; i++ {
		data.WriteByte(0)
	}
}
