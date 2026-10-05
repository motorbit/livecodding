package httpapi

import (
	"bufio"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// documentedOperations reads openapi.yaml without a YAML library: under the top-level "paths:"
// key, 2-space keys are paths and 4-space keys are methods (or "parameters").
func documentedOperations(t *testing.T) map[Route]bool {
	t.Helper()
	f, err := os.Open(filepath.Join("..", "..", "openapi.yaml"))
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	ops := map[Route]bool{}
	inPaths, path := false, ""
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := sc.Text()
		if line == "" || strings.HasPrefix(strings.TrimSpace(line), "#") {
			continue
		}
		indent := len(line) - len(strings.TrimLeft(line, " "))
		key, _, _ := strings.Cut(strings.TrimSpace(line), ":")
		switch {
		case indent == 0:
			inPaths = key == "paths"
		case inPaths && indent == 2:
			path = key
		case inPaths && indent == 4 && key != "parameters":
			ops[Route{Method: strings.ToUpper(key), Path: path}] = true
		}
	}
	if err := sc.Err(); err != nil {
		t.Fatal(err)
	}
	return ops
}

func TestOpenAPIDocumentsEveryRoute(t *testing.T) {
	documented := documentedOperations(t)
	for _, r := range Routes() {
		if !documented[r] {
			t.Errorf("route %s is not documented in openapi.yaml", r.Pattern())
		}
		delete(documented, r)
	}
	for r := range documented {
		t.Errorf("openapi.yaml documents %s, which is not registered", r.Pattern())
	}
}
