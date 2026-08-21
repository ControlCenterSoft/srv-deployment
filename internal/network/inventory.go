package network

import (
	"net"
	"sort"
	"strings"
)

// Interface is the stable, read-only representation of an operating-system
// network interface exposed by Control Center. It deliberately contains no
// mutable configuration so discovery cannot change host connectivity.
type Interface struct {
	Name            string   `json:"name"`
	Index           int      `json:"index"`
	MTU             int      `json:"mtu"`
	HardwareAddress string   `json:"hardware_address,omitempty"`
	Flags           []string `json:"flags"`
	Addresses       []string `json:"addresses"`
}

// Inventory returns a deterministic snapshot of host network interfaces.
func Inventory() ([]Interface, error) {
	interfaces, err := net.Interfaces()
	if err != nil {
		return nil, err
	}
	out := make([]Interface, 0, len(interfaces))
	for _, item := range interfaces {
		addresses, err := item.Addrs()
		if err != nil {
			return nil, err
		}
		addressStrings := make([]string, 0, len(addresses))
		for _, address := range addresses {
			addressStrings = append(addressStrings, address.String())
		}
		sort.Strings(addressStrings)

		flags := flagStrings(item.Flags)
		out = append(out, Interface{
			Name:            item.Name,
			Index:           item.Index,
			MTU:             item.MTU,
			HardwareAddress: strings.ToLower(item.HardwareAddr.String()),
			Flags:           flags,
			Addresses:       addressStrings,
		})
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].Index == out[j].Index {
			return out[i].Name < out[j].Name
		}
		return out[i].Index < out[j].Index
	})
	return out, nil
}

func flagStrings(flags net.Flags) []string {
	ordered := []struct {
		flag net.Flags
		name string
	}{
		{net.FlagUp, "up"},
		{net.FlagBroadcast, "broadcast"},
		{net.FlagLoopback, "loopback"},
		{net.FlagPointToPoint, "point_to_point"},
		{net.FlagMulticast, "multicast"},
		{net.FlagRunning, "running"},
	}
	out := make([]string, 0, len(ordered))
	for _, candidate := range ordered {
		if flags&candidate.flag != 0 {
			out = append(out, candidate.name)
		}
	}
	return out
}
