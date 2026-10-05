package task

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"strings"
)

// ErrInvalidID is returned for strings that are not 8-4-4-4-12 hex UUIDs.
var ErrInvalidID = errors.New("invalid id")

// NewID returns a random (version 4) UUID in canonical upper-case form, like Swift's
// UUID().uuidString.
func NewID() string {
	var b [16]byte
	_, _ = rand.Read(b[:]) // crypto/rand.Read never returns an error.
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	return format(b)
}

// ParseID accepts an 8-4-4-4-12 hex UUID in any letter case and returns its canonical upper-case
// form.
func ParseID(s string) (string, error) {
	if len(s) != 36 || s[8] != '-' || s[13] != '-' || s[18] != '-' || s[23] != '-' {
		return "", ErrInvalidID
	}
	var b [16]byte
	if _, err := hex.Decode(b[:], []byte(s[0:8]+s[9:13]+s[14:18]+s[19:23]+s[24:36])); err != nil {
		return "", ErrInvalidID
	}
	return format(b), nil
}

func format(b [16]byte) string {
	h := strings.ToUpper(hex.EncodeToString(b[:]))
	return h[0:8] + "-" + h[8:12] + "-" + h[12:16] + "-" + h[16:20] + "-" + h[20:32]
}
