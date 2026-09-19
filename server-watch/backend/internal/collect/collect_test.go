package collect

import "testing"

func TestNormalizeTemp(t *testing.T) {
	cases := []struct {
		in, want float64
	}{
		{42000, 42},
		{42, 42},
		{-5000, -5},
	}
	for _, tc := range cases {
		if got := normalizeTemp(tc.in); got != tc.want {
			t.Fatalf("normalizeTemp(%v)=%v want %v", tc.in, got, tc.want)
		}
	}
}

func TestSignalPctFromDbm(t *testing.T) {
	cases := []struct {
		in, want int
	}{
		{-110, 0},
		{-100, 0},
		{-75, 50},
		{-50, 100},
		{-35, 100},
	}
	for _, tc := range cases {
		if got := signalPctFromDbm(tc.in); got != tc.want {
			t.Fatalf("signalPctFromDbm(%d)=%d want %d", tc.in, got, tc.want)
		}
	}
}

func TestRingOrderAndLimit(t *testing.T) {
	r := NewRing(3)
	for _, v := range []float64{1, 2, 3, 4} {
		r.Add(v)
	}
	got := r.Values()
	want := []float64{2, 3, 4}
	if len(got) != len(want) {
		t.Fatalf("len=%d want %d", len(got), len(want))
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("[%d]=%v want %v", i, got[i], want[i])
		}
	}
}
