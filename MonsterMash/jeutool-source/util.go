// Copyright 2018 Andrew Apted.
// This code is under the GNU General Public License, version 3
// or (at your option) any later version.

package main

import "os"
import "fmt"
import "path/filepath"
import "strings"
import "unicode"

// OK is a constant to make code more readable
var Ok error = nil

func Abs(a int) int {
	if a < 0 {
		return -a
	} else {
		return a
	}
}

func Min(a, b int) int {
	if a < b {
		return a
	} else {
		return b
	}
}

func Max(a, b int) int {
	if a > b {
		return a
	} else {
		return b
	}
}

func Pluralize(count int, word string) string {
	if count == 0 {
		return "no " + word + "s"
	} else if count == 1 {
		return "1 " + word
	} else {
		return fmt.Sprintf("%d %ss", count, word)
	}
}

func SafeClose(f *os.File, filename string) {
	err := f.Close()

	if err != nil {
		Failure("   closing %s : %s", filepath.Base(filename), err.Error())
	}
}

//----------------------------------------------------------------------

func RawWord(b []byte) uint16 {
	return uint16(b[0]) | (uint16(b[1]) << 8)
}

func RawLong(b []byte) uint32 {
	return uint32(b[0]) |
		(uint32(b[1]) << 8) |
		(uint32(b[2]) << 16) |
		(uint32(b[3]) << 24)
}

func RawString(b []byte) string {
	count := 0

	for count < len(b) && b[count] != 0 {
		count++
	}

	return string(b[0:count])
}

func StoreWord(b []byte, x uint16) {
	b[0] = byte(x)
	b[1] = byte(x >> 8)
}

func StoreLong(b []byte, x uint32) {
	b[0] = byte(x)
	b[1] = byte(x >> 8)
	b[2] = byte(x >> 16)
	b[3] = byte(x >> 24)
}

func StoreString(b []byte, s string) {
	for i := 0; i < len(b); i++ {
		if i < len(s) {
			b[i] = s[i]
		} else {
			b[i] = 0
		}
	}
}

//----------------------------------------------------------------------

func ValidateWadFilename(fn string) error {
	base := filepath.Base(fn)

	if fn == "" || base == "." || base == ".." ||
		base == "/" || base == "\\" {
		return fmt.Errorf("bad or empty filename")
	}

	if !HasExtension(fn, "wad") {
		return fmt.Errorf("filename is missing .wad extension")
	}

	return Ok
}

func ValidateDirName(dir string) error {
	base := filepath.Base(dir)

	if dir == "" || dir == "." ||
		base == "." || base == ".." ||
		base == "/" || base == "\\" {
		return fmt.Errorf("bad or empty directory name")
	}

	return Ok
}

func DeduceExtractionDir(fn string) string {
	// just remove the extension
	ext := filepath.Ext(fn)
	return fn[0 : len(fn)-len(ext)]
}

func HasExtension(fn, ext string) bool {
	fn = filepath.Ext(fn)
	fn = strings.ToLower(fn)

	if len(fn) > 0 && fn[0] == '.' {
		fn = fn[1:]
	}

	return (fn == ext)
}

func EncodeLumpName(dir, lump, ext string, noconv bool, x, y int) string {
	// NOTE: a backslash ('\') is converted to a carat ('^'),
	//       since his has become a common convention with
	//       DOOM source ports.

	if Options.lowercase {
		lump = strings.ToLower(lump)
	} else {
		lump = strings.ToUpper(lump)
	}

	ext = strings.ToLower(ext)

	var sb strings.Builder

	if noconv {
		sb.WriteByte('=')
	}

	for _, ch := range []byte(lump) {
		if ch == '\\' {
			sb.WriteByte('^')
		} else if ValidFileChar(rune(ch)) {
			sb.WriteByte(ch)
		} else {
			// percent escape it
			fmt.Fprintf(&sb, "%%%02X", ch)
		}
	}

	// prevent an empty file name
	if sb.Len() == 0 {
		sb.WriteString("_")
	}

	if x != 0 || y != 0 {
		fmt.Fprintf(&sb, ",%d,%d", x, y)
	}

	// baseName is the name portion before the extension
	baseName := sb.String()

	// Build the initial filename and check for duplicates.
	// If a file already exists, append a numeric infix: NAME.1.ext, NAME.2.ext, etc.
	filename := baseName
	if ext != "" {
		filename = baseName + "." + ext
	}

	if dir != "" {
		filename = filepath.Join(dir, filename)
	}

	suffix := 1
	for {
		if _, err := os.Stat(filename); os.IsNotExist(err) {
			break
		}
		// File exists, try next suffix: e.g. DECORATE.1.raw, DECORATE.2.raw
		if ext != "" {
			filename = filepath.Join(dir, fmt.Sprintf("%s.%d.%s", baseName, suffix, ext))
		} else {
			filename = filepath.Join(dir, fmt.Sprintf("%s.%d", baseName, suffix))
		}
		suffix++
	}

	return filename
}

func DecodeLumpName(filename string) (lump, ext string, noconv bool, x, y int, err error) {
	// the input filename should not contain directories.

	ext = filepath.Ext(filename)
	ext = strings.ToLower(ext)

	// remove starting dot from the extension
	if len(ext) > 0 && ext[0] == '.' {
		ext = ext[1:]
	}

	// files beginning with '=' are added without conversion
	if len(filename) > 0 && filename[0] == '=' {
		noconv = true
		filename = filename[1:]
	}

	var sb strings.Builder

	for pos := 0; pos < len(filename); pos++ {
		ch := filename[pos]

		// if we hit the extension, we are done
		if ch == '.' {
			break
		}

		if ch == ',' {
			n, _ := fmt.Sscanf(filename[pos:], ",%d,%d", &x, &y)

			if n != 2 {
				err = fmt.Errorf("bad offsets in filename: '%s'", filename)
				return
			}

			// nothing can occur after the offsets
			break
		}

		// see the NOTE in EncodeLumpName() above
		if ch == '^' {
			ch = '\\'
		}

		if ch == '%' && pos+2 < len(filename) {
			n1 := filename[pos+1]
			n2 := filename[pos+2]

			d1 := DecodeHexDigit(rune(n1))
			d2 := DecodeHexDigit(rune(n2))

			if d1 < 0 || d2 < 0 {
				err = fmt.Errorf("bad percent escape in filename: '%s'", filename)
				return
			} else {
				ch = byte(d1*16 + d2)
				pos += 2
			}
		}

		sb.WriteByte(ch)
	}

	lump = strings.ToUpper(sb.String())

	if lump == "" {
		err = fmt.Errorf("bad or empty filename: '%s'", filename)
		return
	}
	if len(lump) > 8 {
		err = fmt.Errorf("lump name is too long: '%s'", filename)
		return
	}

	return
}

func ValidFileChar(ch rune) bool {
	// NOTE: this is quite conservative

	if unicode.IsDigit(ch) {
		return true
	}
	if unicode.IsLetter(ch) {
		return true
	}

	switch ch {
	case '_', '-', '+', '@', '[', ']':
		return true
	default:
		return false
	}
}

func DecodeHexDigit(ch rune) int {
	if '0' <= ch && ch <= '9' {
		return int(ch) - '0'
	} else if 'A' <= ch && ch <= 'F' {
		return 10 + int(ch) - 'A'
	} else if 'a' <= ch && ch <= 'f' {
		return 10 + int(ch) - 'a'
	} else {
		// not a hex digit
		return -1
	}
}
