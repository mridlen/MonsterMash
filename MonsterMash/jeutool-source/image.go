// Copyright 2018 Andrew Apted.
// This code is under the GNU General Public License, version 3
// or (at your option) any later version.

package main

import "os"
import "fmt"
import "sort"

import "strings"
import "strconv"
import "path/filepath"

import "image"
import "image/png"
import "image/color"

// RAWPIX_Load reads a PNG image file and converts it into a
// raw block of pixels.  The size of the PNG image is also
// returned, so the caller can check whether it makes sense.
// Each output byte refers to a color in the current palette.
// Any error reading the file is returned immediately.
func RAWPIX_Load(filename string) (data []byte, W, H int, err error) {
	f, err := os.Open(filename)
	if err != nil {
		return
	}
	defer f.Close()

	img, err := png.Decode(f)
	if err != nil {
		return
	}

	W = img.Bounds().Dx()
	H = img.Bounds().Dy()

	LX := img.Bounds().Min.X
	LY := img.Bounds().Min.Y

	total := W * H

	data = make([]byte, total)

	for i := 0; i < total; i++ {
		x := i % W
		y := i / W

		rawcol := img.At(LX+x, LY+y)

		data[i] = PaletteLookup(rawcol)
	}

	return
}

// RAWPIX_Save writes a block of raw pixels to a PNG image file.
// The W and H parameters are the width and height of the image.
// Each input byte refers to a color in the current palette.
// Any writing error will be returned immediately.
func RAWPIX_Save(filename string, data []byte, W, H int) error {
	total := W * H
	if total > len(data) {
		panic("RAWPIX_Save: not enough data")
	}

	f, err := os.Create(filename)
	if err != nil {
		return err
	}

	defer SafeClose(f, filename)

	img := image.NewNRGBA(image.Rect(0, 0, W, H))

	for i := 0; i < total; i++ {
		x := i % W
		y := i / W

		pix := int(data[i])

		img.SetNRGBA(x, y, palette[pix])
	}

	return png.Encode(f, img)
}

//----------------------------------------------------------------------

// the column drawers in the DOOM engine are limited to this
const MAX_POST_LEN = 128

func PATCH_GetOffsets(data []byte) (OX, OY int) {
	if len(data) >= 8 {
		// the X/Y offsets can be negative
		OX = int(int16(RawWord(data[4:])))
		OY = int(int16(RawWord(data[6:])))
	}
	return
}

// PATCH_Save writes an image in DOOM's raw patch format into a
// PNG image file.
func PATCH_Save(filename string, data []byte) error {
	if len(data) < 8 {
		return fmt.Errorf("bad patch lump (way too small)")
	}

	basename := filepath.Base(filename)

	W := int(RawWord(data[0:]))
	H := int(RawWord(data[2:]))

	// double check W and H are valid
	// [ the first check was by IdentifyPatchLump ]
	if W == 0 || W > 4096 || H == 0 || H > 2048 {
		return fmt.Errorf("bad patch lump (bad size %dx%d)", W, H)
	}

	if len(data) < 8+W*4 {
		return fmt.Errorf("bad patch lump (too small)")
	}

	img := image.NewNRGBA(image.Rect(0, 0, W, H))

	// draw each column into the image.
	// [ the base image is already transparent ]

	for x := 0; x < W; x++ {
		PATCH_DecodeColumn(img, x, H, data, basename)
	}

	f, err := os.Create(filename)
	if err != nil {
		return err
	}

	defer SafeClose(f, filename)

	return png.Encode(f, img)
}

func PATCH_DecodeColumn(img *image.NRGBA, x, H int, data []byte, basename string) {
	offset := int(RawLong(data[8+x*4:]))

	if offset >= len(data) {
		Warning("   %s: bad offset in patch (column %d)", basename, x)
		return
	}

	// each column consists of a series of "posts" of pixels.
	// TODO : describe in more detail

	column := data[offset:]

	top := -1

	for {
		// this sentinel marks the end of a column
		if column[0] == 0xFF {
			return
		}

		if len(column) < 4 {
			// bad post
			break
		}

		delta := int(column[0])

		// logic for DeePsea's tall patches
		if delta <= top {
			top += delta
		} else {
			top = delta
		}

		length := int(column[1])

		// each post has a dummmy pixel above and below the run
		// of pixels.  we need to ignore them.
		column = column[3:]

		if len(column) < length+2 {
			// bad post
			break
		}

		for i := 0; i < length; i++ {
			y := top + i

			if y < 0 {
				continue
			} else if y >= H {
				break
			}

			pix := column[i]

			img.SetNRGBA(x, y, palette[pix])
		}

		column = column[length+1:]
	}

	Warning("   %s: bad post in patch (column %d)", basename, x)
}

// PATCH_Load reads a PNG image file and converts it to DOOM's
// raw patch format.  The size of the original image is also
// returned.
func PATCH_Load(filename string, OX, OY int) (data []byte, W, H int, err error) {
	f, err := os.Open(filename)
	if err != nil {
		return
	}

	defer f.Close()

	img, err := png.Decode(f)
	if err != nil {
		return
	}

	W = img.Bounds().Dx()
	H = img.Bounds().Dy()

	LX := img.Bounds().Min.X
	LY := img.Bounds().Min.Y

	reserve := 16 + W*(H+4) + W*H/2

	// create enough data for the header and W column offsets.
	// the actual columns are appended later.
	data = make([]byte, 8+W*4, reserve)

	StoreWord(data[0:], uint16(W))
	StoreWord(data[2:], uint16(H))
	StoreWord(data[4:], uint16(OX))
	StoreWord(data[6:], uint16(OY))

	for x := 0; x < W; x++ {
		offset := len(data)
		StoreLong(data[8+x*4:], uint32(offset))

		column := PATCH_EncodeColumn(x, H, LX, LY, img)
		data = append(data, column...)
	}

	return
}

func PATCH_EncodeColumn(x, H, LX, LY int, img image.Image) []byte {
	column := make([]byte, 0, 16+H+H/2)

	var post [MAX_POST_LEN]byte

	last_top := 0
	y := 0

	for y < H {
		rawcol := img.At(LX+x, LY+y)

		// skip transparent pixels
		if _, _, _, A := rawcol.RGBA(); A < 0xeeee {
			y++
			continue
		}

		// grab the next post, a run of non-transparent pixels
		top := y
		count := 0

		for y < H && count < MAX_POST_LEN {
			rawcol := img.At(LX+x, LY+y)
			if _, _, _, A := rawcol.RGBA(); A < 0xeeee {
				break
			}

			post[count] = PaletteLookup(rawcol)
			count++

			y++
		}

		use_top := top

		// logic to create "tall patches"
		if top > 254 {
			for {
				delta := top - last_top

				// when delta < last_top, it can be used as-is,
				// otherwise need to add some empty posts.
				if delta < last_top {
					use_top = delta
					break
				}

				if last_top < 254 {
					column = append(column, 254, 0, 0, 0)
					last_top = 254
					continue
				}

				column = append(column, 252, 0, 0, 0)
				last_top += 252
			}
		}

		column = append(column, byte(use_top), byte(count))

		// each post has a duplicate pixel above and below the post
		column = append(column, post[0])
		column = append(column, post[0:count]...)
		column = append(column, post[count-1])

		last_top = top
	}

	// terminate column with the sentinal
	column = append(column, 0xFF)

	return column
}

//----------------------------------------------------------------------

// ansi_remap table just swaps bits 0 and 2
var ansi_remap [8]byte = [8]byte{0, 4, 2, 6, 1, 5, 3, 7}

// ANSI_Decode converts the raw bytes of a CGA text mode screen
// (80x25 characters with color attributes) to an ".ans" file
// containing escape codes for color and CP437 characters.
//
// The input data will generally be 4000 bytes, but this is not
// enforced here.
//
// NOTE: there are no line-breaks (CR/LF) in the output file,
// since we require the full 80 characters across, and programs
// like "ansilove" will automatically move to a new line when 80
// characters is reached.
func ANSI_Decode(data []byte) []byte {
	var sb strings.Builder

	// always begin each file with a color reset
	sb.WriteString("\x1B[0m")

	x := 0
	last_attr := byte(7)

	for len(data) >= 2 {
		ch := data[0]
		attr := data[1]
		data = data[2:]

		// handle attribute changes.
		// this is tricky since we cannot reset bold mode without
		// also resetting the FG and BG colors.
		//
		// NOTE: we ignore the blink bit (0x80)

		if attr != last_attr {
			new_fg := (attr & 0x07) != (last_attr & 0x07)
			new_bg := (attr & 0x70) != (last_attr & 0x70)
			new_em := (attr & 0x08) != (last_attr & 0x08)

			sb.WriteString("\x1B[")

			// special case of only setting the bold bit
			if new_em && (attr&8) == 8 && !new_fg && !new_bg {
				sb.WriteByte('1')
				new_em = false
			}

			if new_em {
				sb.WriteByte('0' + ((attr & 8) >> 3))
				sb.WriteByte(';')

				new_fg = true
				new_bg = true
			}

			if new_bg {
				sb.WriteByte('4')
				sb.WriteByte('0' + ansi_remap[(attr&0x70)>>4])
			}
			if new_bg && new_fg {
				sb.WriteByte(';')
			}
			if new_fg {
				sb.WriteByte('3')
				sb.WriteByte('0' + ansi_remap[attr&7])
			}

			sb.WriteByte('m')

			last_attr = attr
		}

		// remap some troublesome chars, especially NUL
		switch ch {
		case 0:
			ch = ' '
		case 9:
			ch = 'O'
		case 10:
			ch = 8
		case 13:
			ch = 14
		case 26:
			ch = 16
		case 27:
			ch = 17
		}

		sb.WriteByte(ch)

		x++
		if x >= 80 {
			// see comments above why we don't add "\r\n" here
			x = 0
		}
	}

	// end with a color reset and ^Z (break) char.
	// [ both of these seem common, but neither is compulsory ]
	sb.WriteString("\x1B[0m")
	sb.WriteString("\x1A")

	return []byte(sb.String())
}

// ANSI_Encode converts an ".ans" file containing escape codes
// for color plus characters in the CP437 charset into a CGA text
// mode screen (80x25 characters with color attributes).
//
// The result here is always 4000 bytes (for a 80x25 text mode).
// Lines which are shorter than 80 columns get padded with blanks,
// and longer lines will wrap around.  Similarly, missing rows
// are padded, and excess rows are discarded.
//
// NOTE: this parser is quite dumb, it cannot handle all of the
// escape sequences which programs like "ansilove" can.  The
// primary goal is to reconstruct screens previously extracted
// by this program.
func ANSI_Encode(data []byte) (res []byte) {
	res = make([]byte, 4000)

	// cursor position
	x, y := 0, 0

	// normal text is black background, gray foreground
	attr := byte(7)

	for len(data) > 0 {
		ch := data[0]
		data = data[1:]

		// the ^Z character is a terminator.
		// [ and it is often followed by some SAUCE-y info ]
		if ch == '\x1A' {
			break
		}

		// an ANSI CSI ("escape") sequence?
		if ch == '\x1B' && len(data) >= 2 && data[0] == '[' {
			data = data[1:]

			// find the end of the sequence
			end := 0
			for end+1 < len(data) && end+1 < 16 && data[end] < 0x40 {
				end++
			}

			cmd := data[end]

			// get the parameter numbers
			parms := strings.Split(string(data[0:end]), ";")
			if len(parms) == 1 && parms[0] == "" {
				parms = []string{}
			}

			move := 1
			if len(parms) > 0 {
				move, _ = strconv.Atoi(parms[0])
			}

			// we handle the "m" (set color) and "A"-"D" (move cursor)
			// commands.  all other commands are ignored.
			switch cmd {
			case 'm':
				// no parameter is equivalent to zero
				if len(parms) == 0 {
					attr = 7
				} else {
					for _, p := range parms {
						val, err := strconv.Atoi(p)
						if err != nil {
							// ignore malformed value
						} else if val == 0 {
							attr = 7
						} else if val == 1 {
							attr |= 8
						} else if 30 <= val && val <= 37 {
							// set foreground
							fg := ansi_remap[val-30]
							attr = (attr & 0x78) | fg
						} else if 40 <= val && val <= 47 {
							// set background
							bg := ansi_remap[val-40]
							attr = (attr & 0x0F) | (bg << 4)
						}
					}
				}
			case 'A':
				y -= move
			case 'B':
				y += move
			case 'C':
				x += move
			case 'D':
				x -= move
			}

			// clamp cursor pos
			if x < 0 {
				x = 0
			}
			if y < 0 {
				y = 0
			}

			data = data[end+1:]
			continue
		}

		// carriage returns are ignored
		if ch == '\r' {
			continue
		}

		// newline?
		if ch == '\n' {
			x = 0
			y++
			continue
		}

		// everything else is a character to store
		if x < 80 && y < 25 {
			res[y*160+x*2+0] = ch
			res[y*160+x*2+1] = attr
		}

		x++
		if x >= 80 {
			x = 0
			y++
		}
	}

	return
}

//----------------------------------------------------------------------

func HexenSTARTUP_Save(filename string, data []byte) error {
	// double check the size
	if len(data) != (640*480/2 + 16*3) {
		return fmt.Errorf("wrong lump size (got %d)", len(data))
	}

	var palette [16]color.NRGBA

	for c := 0; c < 16; c++ {
		// the color intensities are 6-bit, so convert to 8-bit
		palette[c].R = data[c*3+0] * 4
		palette[c].G = data[c*3+1] * 4
		palette[c].B = data[c*3+2] * 4
		palette[c].A = 255
	}

	data = data[48:]

	img := image.NewNRGBA(image.Rect(0, 0, 640, 480))

	for x := 0; x < 640; x++ {
		for y := 0; y < 480; y++ {
			ofs := (x >> 3) + y*80
			bit := byte(1 << byte((x&7)^7))
			pix := 0

			for plane := 0; plane < 4; plane++ {
				k := data[plane*480*80+ofs] & bit
				if k != 0 {
					pix |= (1 << byte(plane))
				}
			}

			img.SetNRGBA(x, y, palette[pix])
		}
	}

	f, err := os.Create(filename)
	if err != nil {
		return err
	}
	defer SafeClose(f, filename)

	return png.Encode(f, img)
}

func HexenSTARTUP_Load(filename string) (data []byte, err error) {
	// we use the global palette (in palette.go) here to process
	// the 16-color palette of the STARTUP image, so we need to
	// save the global palette and restore it when done.
	PalettePush()

	defer PalettePop()

	f, err := os.Open(filename)
	if err != nil {
		return
	}
	defer f.Close()

	img, err := png.Decode(f)
	if err != nil {
		return
	}

	W := img.Bounds().Dx()
	H := img.Bounds().Dy()

	if W != 640 || H != 480 {
		err = fmt.Errorf("wrong image size (%dx%d)", W, H)
		return
	}

	LX := img.Bounds().Min.X
	LY := img.Bounds().Min.Y

	data = make([]byte, 640*480/2+16*3)

	/* step 1: determine if the image uses more than 16 colors */

	// we are relying on using len() on a map[xxx] to tell us the
	// current number of distinct colors in the bucket.
	bucket := make(map[uint32]bool)

	for x := 0; x < W; x++ {
		for y := 0; y < H; y++ {
			r, g, b, _ := img.At(LX+x, LY+y).RGBA()

			r >>= 10 // reduce to 6-bits each
			g >>= 10 //
			b >>= 10 //

			bc := (r << 16) | (g << 8) | b

			bucket[bc] = true
		}

		// exit early when the bucket has overflowed
		if len(bucket) > 16 {
			break
		}
	}

	/* step 2: create the 16-color palette */

	HexenSTARTUP_MakePalette(bucket, data)

	/* step 3: transfer the pixels to 4-bit planar gfx */

	for x := 0; x < 640; x++ {
		for y := 0; y < 480; y++ {
			ofs := (x >> 3) + y*80
			bit := byte(1 << byte((x&7)^7))

			rawcol := img.At(LX+x, LY+y)
			pix := PaletteLookup(rawcol)

			for plane := 0; plane < 4; plane++ {
				k := pix & (1 << byte(plane))
				if k != 0 {
					data[48+plane*480*80+ofs] |= bit
				}
			}
		}
	}

	return
}

func HexenSTARTUP_MakePalette(bucket map[uint32]bool, data []byte) {
	size := len(bucket)

	if size > 16 {
		// use a hard-coded 16-color palette
		Warning("   STARTUP.png has over 16 colors, using built-in palette")

		bucket = make(map[uint32]bool)

		bucket[0x000000] = true
		bucket[0x101010] = true
		bucket[0x202020] = true
		bucket[0x303030] = true
		bucket[0x3f3f3f] = true

		bucket[0x0c0026] = true
		bucket[0x000033] = true
		bucket[0x00263f] = true
		bucket[0x001900] = true
		bucket[0x002a00] = true

		bucket[0x190c00] = true
		bucket[0x26190c] = true
		bucket[0x370000] = true
		bucket[0x3f0026] = true
		bucket[0x3f1900] = true
		bucket[0x3f3f00] = true

		size = 16
	}

	// pad out the bucket when small
	// (for the benefit of the NOTCH graphics)
	if size < 16 {
		bucket[0x000000] = true

		if size <= 14 {
			bucket[0x3f3f3f] = true
		}

		if size <= 10 {
			bucket[0x080808] = true
			bucket[0x101010] = true
			bucket[0x202020] = true
			bucket[0x303030] = true
		}
	}

	// transfer bucket colors to an array
	raw_colors := make([]uint32, 0, 16)

	for col := range bucket {
		raw_colors = append(raw_colors, col)
	}

	// we *need* 16 colors, duplicate some colors if we have less
	for len(raw_colors) < 8 {
		raw_colors = append(raw_colors, 0x000000)
	}
	for len(raw_colors) < 16 {
		col := raw_colors[len(raw_colors)-8]
		raw_colors = append(raw_colors, col)
	}

	calc_ity := func(i int) int {
		r := byte(raw_colors[i] >> 16)
		g := byte(raw_colors[i] >> 8)
		b := byte(raw_colors[i])
		return int(r)*3 + int(g)*5 + int(b)*2
	}

	// sort the raw_colors by their intensity
	sort.Slice(raw_colors, func(i, k int) bool {
		return calc_ity(i) < calc_ity(k)
	})

	// this remapping moves the sorted colors to make the final
	// palette of 16-colors match the intensities of the STARTUP
	// lump in the Hexen IWAD.  For example, the original palette
	// has darkest color at index #0 and brightest at index #8.
	remap := [16]int{0, 15, 6, 5, 9, 2, 3, 7, 1, 4, 13, 12, 10, 11, 14, 8}

	for i := 0; i < 16; i++ {
		dest := remap[i]

		raw := raw_colors[i]

		r := byte(raw >> 16)
		g := byte(raw >> 8)
		b := byte(raw)

		// store the colors in the lump, using 6-bit values
		data[dest*3+0] = r
		data[dest*3+1] = g
		data[dest*3+2] = b

		// store in the global palette, need 8-bit values
		palette[dest] = color.NRGBA{r * 4, g * 4, b * 4, 255}
	}

	// the global palette has 256 entries, so pad it out
	for c := 16; c < 256; c++ {
		palette[c] = palette[15]
	}

	PaletteCreateHash()

	// len(pal_hash) should be 16 now
}
