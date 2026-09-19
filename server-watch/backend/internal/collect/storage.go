package collect

import (
	"os"
	"strings"
	"syscall"
)

type StorageStat struct {
	Mount     string  `json:"mount"`
	Device    string  `json:"device"`
	FSType    string  `json:"fs_type"`
	TotalB    uint64  `json:"total_b"`
	UsedB     uint64  `json:"used_b"`
	AvailB    uint64  `json:"avail_b"`
	UsedPct   float64 `json:"used_pct"`
}

var pseudoFS = map[string]bool{
	"proc": true, "sysfs": true, "tmpfs": true, "devtmpfs": true,
	"devpts": true, "cgroup": true, "cgroup2": true, "overlay": true,
	"debugfs": true, "tracefs": true, "securityfs": true, "pstore": true,
	"bpf": true, "configfs": true, "fusectl": true, "mqueue": true,
	"hugetlbfs": true, "ramfs": true, "selinuxfs": true, "nsfs": true,
	"autofs": true, "binfmt_misc": true, "functionfs": true, "fuse.gvfsd-fuse": true,
	"fuse.fuse-overlayfs": true, "efivarfs": true, "rpc_pipefs": true,
}

func SampleStorage() []StorageStat {
	data, err := os.ReadFile("/proc/self/mounts")
	if err != nil {
		return nil
	}
	seen := map[string]bool{}
	var out []StorageStat
	for _, line := range strings.Split(string(data), "\n") {
		f := strings.Fields(line)
		if len(f) < 3 {
			continue
		}
		dev, mount, fstype := f[0], unescapeMount(f[1]), f[2]
		if pseudoFS[fstype] {
			continue
		}
		if !strings.HasPrefix(dev, "/dev/") {
			continue
		}
		if seen[dev] && mount != "/" {
			continue
		}
		var st syscall.Statfs_t
		if err := syscall.Statfs(mount, &st); err != nil {
			continue
		}
		total := st.Blocks * uint64(st.Bsize)
		avail := st.Bavail * uint64(st.Bsize)
		free := st.Bfree * uint64(st.Bsize)
		if total == 0 {
			continue
		}
		used := total - free
		pct := float64(used) / float64(total) * 100
		out = append(out, StorageStat{
			Mount: mount, Device: dev, FSType: fstype,
			TotalB: total, UsedB: used, AvailB: avail, UsedPct: pct,
		})
		seen[dev] = true
	}
	return out
}

func unescapeMount(s string) string {
	r := strings.NewReplacer(`\040`, " ", `\011`, "\t", `\012`, "\n", `\134`, `\`)
	return r.Replace(s)
}
