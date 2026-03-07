// Copyright 2018 Andrew Apted.
// This code is under the GNU General Public License, version 3
// or (at your option) any later version.

package main

import "os"
import "fmt"
import "bytes"
import "strings"
import "path/filepath"

func TEXTURE_Save(filename string, data []byte, pnames []string) error {
	f, err := os.Create(filename)
	if err != nil {
		return err
	}
	defer SafeClose(f, filename)

	fmt.Fprintf(f, ";\n")
	fmt.Fprintf(f, "; texture definitions\n")
	fmt.Fprintf(f, ";\n")

	if len(data) < 4 {
		return fmt.Errorf("too short")
	}

	count := int(RawLong(data[0:]))

	if count == 0 {
		fmt.Fprintf(f, "; none!\n")
		return Ok
	}

	if len(data) < 4+count*(4+18) {
		return fmt.Errorf("too short")
	}

	is_strife := TEXTURE_DetectStrife(data)

	if is_strife {
		Config.strife_tex = true
	}

	// read the offsets
	offsets := make([]int, count)

	for i := 0; i < count; i++ {
		ofs := int(RawLong(data[4+i*4:]))

		if ofs < 4+count*4 || ofs >= len(data) {
			return fmt.Errorf("bad offset (%d)", ofs)
		}

		offsets[i] = ofs
	}

	// convert each entry...
	for i := 0; i < count; i++ {
		err := TEXTURE_DecodeEntry(f, data[offsets[i]:], pnames, is_strife)
		if err != nil {
			return err
		}
	}

	fmt.Fprintf(f, "; the end\n")
	return Ok
}

// TEXTURE_DetectStrife detects whether the TEXTURE1 or TEXTURE2 lump
// lump is in Strife format.  Strife versions 1.1 and later use a more
// compact form of these lumps, removing some unused fields from the
// texture and patch definitions.  Hence we need to determine which
// format is in use.
//
// This code follows the ZDoom logic: check ALL the texture entries
// assuming DOOM format, and if any have a weird patch_count or the
// last two bytes of columndir are non-zero then assume Strife.
func TEXTURE_DetectStrife(data []byte) bool {
	if len(data) < 4 {
		return false // lump is short or corrupted
	}

	count := int(RawLong(data[0:]))

	if count == 0 {
		// cannot tell when none, so assume DOOM
		return false
	}

	if len(data) < 4+count*(4+18) {
		return false // lump is short or corrupted
	}

	for i := 0; i < count; i++ {
		ofs := int(RawLong(data[4+i*4:]))

		// ignore bad offsets here
		if ofs < 4*count || ofs >= len(data) {
			continue
		}

		entry := data[ofs:]

		// last entry can only be short in Strife format
		if len(entry) == 18 {
			return true
		}

		if len(entry) < 22 {
			continue
		}

		// number of patches is weird?
		if entry[21] > 0x10 {
			return true
		}
		if RawWord(entry[18:]) != 0 {
			return true
		}
	}

	return false
}

func TEXTURE_DecodeEntry(f *os.File, entry []byte, pnames []string, is_strife bool) error {
	entry_len := 22
	patch_len := 10

	if is_strife {
		entry_len = 18
		patch_len = 6
	}

	if len(entry) < entry_len {
		Warning("   TEXTURE1/2 : entry too short")
		return Ok
	}

	name := RawString(entry[0:8])

	if name == "" || (len(name) > 0 && name[0] == 0) {
		Warning("   TEXTURE1/2 : texture name is empty")
		return Ok
	}

	W := int(RawWord(entry[12:]))
	H := int(RawWord(entry[14:]))

	if W == 0 || H == 0 || W > 4096 || H > 2048 {
		Warning("   TEXTURE1/2 : texture '%s' has bad size (%dx%d)", name, W, H)
		return Ok
	}

	// these two fields are a ZDoom feature.
	// the original 4-byte field is called 'masked', but it was never
	// actually used by the DOOM engine (always set to zero).
	xscale := int16(RawWord(entry[8:]))
	yscale := int16(RawWord(entry[10:]))

	// begin the texture definition in output file
	var err error

	if xscale != 0 && yscale != 0 {
		// extended format
		_, err = fmt.Fprintf(f, "%-9s %3d %3d %d %d\n", name, W, H, xscale, yscale)
	} else {
		_, err = fmt.Fprintf(f, "%-9s %3d %3d\n", name, W, H)
	}

	if err != nil {
		return err
	}

	// decode each patch.....

	patchnum := int(RawWord(entry[entry_len-2:]))

	if patchnum == 0 {
		Warning("   TEXTURE1/2 : texture '%s' has no patches", name)
		return Ok
	}

	entry = entry[entry_len:]

	for i := 0; i < patchnum; i++ {
		if len(entry) < patch_len {
			Warning("   TEXTURE1/2 : texture '%s' truncated/corrupted", name)
			break
		}

		OX := int16(RawWord(entry[0:]))
		OY := int16(RawWord(entry[2:]))
		PN := int(RawWord(entry[4:]))

		patch := ""
		if PN < len(pnames) {
			patch = pnames[PN]
		} else {
			Warning("   TEXTURE1/2 : texture '%s' has bad pname index (%d)", name, PN)
			patch = fmt.Sprintf("unk_%04d", PN)
		}

		// write the patch definition to output file
		_, err := fmt.Fprintf(f, "*                   %-9s % 4d % 4d\n", patch, OX, OY)
		if err != nil {
			return err
		}

		entry = entry[patch_len:]
	}

	return Ok
}

//----------------------------------------------------------------------

type TexBits struct {
	patch  bool
	name   string
	OX, OY int16 // width and height for texture defs
	count  int16 // number of patches for texture defs
	xscale int16
	yscale int16
}

func TEXTURE_Load(filename string) ([]byte, error) {
	text, err := TXT_Load(filename)
	if err != nil {
		return nil, err
	}

	// simplify filename for warning messages
	filename = filepath.Base(filename)

	// built the texture defs into this buffer
	var defs bytes.Buffer

	// during parsing, these offsets are from start of defs
	// (NOT start of lump), but they are adjusted afterwards.
	offsets := make([]int, 0, 500)

	cur_ofs := -1
	cur_tex := TexBits{}
	cur_patches := make([]TexBits, 0, 64)

	finish_tex := func() error {
		if cur_ofs < 0 {
			// nothing to finish
			return Ok
		}

		// we do not allow textures with no patches
		if len(cur_patches) == 0 {
			return fmt.Errorf("texture '%s' has no patches", cur_tex.name)
		}
		if len(cur_patches) > 32767 {
			return fmt.Errorf("texture '%s' has too many patches", cur_tex.name)
		}

		cur_tex.count = int16(len(cur_patches))

		// check if size is valid
		if cur_tex.OX <= 0 || cur_tex.OX > 4096 ||
			cur_tex.OY <= 0 || cur_tex.OY > 2048 {

			return fmt.Errorf("texture '%s' has bad size (%dx%d)", cur_tex.name,
				cur_tex.OX, cur_tex.OY)
		}

		TEXTURE_AddTextureDef(&defs, cur_tex)

		for _, p := range cur_patches {
			err := TEXTURE_AddPatchDef(&defs, p)
			if err != nil {
				return err
			}
		}

		// reset current texture
		cur_ofs = -1
		cur_tex = TexBits{}
		cur_patches = cur_patches[0:0]

		return Ok
	}

	for {
		var line string

		text, line = SWAN_ParseLine(text)
		if text == nil {
			break
		}

		// skip blank lines and comments
		if line == "" {
			continue
		}

		/* parse the line */

		tb, err := TEXTURE_ParseLine(line)
		if err != nil {
			return nil, err
		}

		if tb.patch {
			// patch definition
			if cur_ofs < 0 {
				return nil, fmt.Errorf("missing texture header")
			}

			cur_patches = append(cur_patches, tb)

		} else {
			// texture definition

			// finish any previous one
			err = finish_tex()
			if err != nil {
				return nil, err
			}

			cur_ofs = defs.Len()
			cur_tex = tb

			offsets = append(offsets, cur_ofs)
		}
	}

	err = finish_tex()
	if err != nil {
		return nil, err
	}

	size := 4 + len(offsets)*4 + defs.Len()
	data := make([]byte, size)

	// store the number of texture defs
	StoreLong(data[0:], uint32(len(offsets)))

	// store the offsets
	for i, ofs := range offsets {
		real_ofs := 4 + len(offsets)*4 + ofs
		StoreLong(data[4+i*4:], uint32(real_ofs))
	}

	// store all the definitions
	copy(data[4+len(offsets)*4:], defs.Bytes())

	return data, Ok
}

func TEXTURE_ParseLine(line string) (TexBits, error) {
	tb := TexBits{}

	line = strings.ToUpper(line)

	if line[0] == '*' {
		tb.patch = true
		line = strings.TrimSpace(line[1:])
	}

	n, _ := fmt.Sscanf(line, "%s %d %d %d %d", &tb.name,
		&tb.OX, &tb.OY, &tb.xscale, &tb.yscale)

	if n < 3 {
		return tb, fmt.Errorf("wrong syntax: %s", line)
	}

	if len(tb.name) > 8 {
		return tb, fmt.Errorf("name too long: %s", tb.name)
	}

	// ok
	return tb, nil
}

func TEXTURE_AddTextureDef(defs *bytes.Buffer, tb TexBits) {
	var buf [22]byte

	StoreString(buf[0:8], tb.name)

	// width and height
	StoreWord(buf[12:], uint16(tb.OX))
	StoreWord(buf[14:], uint16(tb.OY))

	// these two are ZDoom-isms
	StoreWord(buf[8:], uint16(tb.xscale))
	StoreWord(buf[10:], uint16(tb.yscale))

	// Strife v1.1 uses a more compact format
	if Config.strife_tex {
		StoreWord(buf[16:], uint16(tb.count))
		defs.Write(buf[0:18])

	} else {
		StoreWord(buf[20:], uint16(tb.count))
		defs.Write(buf[:])
	}
}

func TEXTURE_AddPatchDef(defs *bytes.Buffer, tb TexBits) error {
	var buf [10]byte

	PN := BuildAddPatchName(tb.name)

	// pname indexes in TEXTUREx are 16-bit *signed* integers
	if PN > 32767 {
		return fmt.Errorf("PNAMES lump overflowed!")
	}

	StoreWord(buf[0:], uint16(tb.OX))
	StoreWord(buf[2:], uint16(tb.OY))
	StoreWord(buf[4:], uint16(PN))

	// Strife v1.1 uses a more compact format
	if Config.strife_tex {
		defs.Write(buf[0:6])
	} else {
		defs.Write(buf[:])
	}

	return Ok
}

//----------------------------------------------------------------------

func PNAMES_Decode(data []byte) (pnames []string, err error) {
	if len(data) < 4 {
		return nil, fmt.Errorf("too short")
	}

	count := int(RawLong(data[0:]))

	data = data[4:]

	// pname indexes in TEXTUREx are 16-bit *signed* integers
	if count > 32767 {
		return nil, fmt.Errorf("too large!")
	}

	if count*8 > len(data) {
		// truncate the count to match lump size
		Warning("   PNAMES seems truncated (%d*8 > lump size)", count)
		count = len(data) / 8
	}

	pnames = make([]string, count)

	for i := 0; i < count; i++ {
		pnames[i] = RawString(data[i*8 : (i+1)*8])

		// prevent completely blank names
		if pnames[i] == "" {
			Warning("   PNAMES contains empty/bad patch name")
			pnames[i] = fmt.Sprintf("bad_%04d", i)
		}
	}

	return
}

func PNAMES_Encode(pnames map[string]int) []byte {
	count := len(pnames)

	data := make([]byte, 4+8*count)

	StoreLong(data[0:], uint32(count))

	for s, i := range pnames {
		if i >= count {
			panic("internal error handling PNAMES")
		}

		StoreString(data[4+i*8:4+i*8+8], s)
	}

	return data
}
