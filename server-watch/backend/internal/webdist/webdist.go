// Package webdist embeds the built Vue frontend (backend/internal/webdist/dist).
package webdist

import (
	"embed"
	"io/fs"
)

//go:embed all:dist
var distFS embed.FS

// FS returns the frontend dist as an fs.FS rooted at the app.
func FS() fs.FS {
	sub, err := fs.Sub(distFS, "dist")
	if err != nil {
		panic(err)
	}
	return sub
}
