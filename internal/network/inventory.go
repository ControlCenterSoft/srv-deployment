package network

import (
	"net"
	"sort"
	"time"
)

const SchemaVersion = 1

type Address struct {
	CIDR string `json:"cidr"`
}

type Interface struct {
	ID           string    `json:"id"`
	Name         string    `json:"name"`
	Index        int       `json:"index"`
	MTU          int       `json:"mtu"`
	MAC          string    `json:"mac,omitempty"`
	Flags        []string  `json:"flags"`
	Addresses    []Address `json:"addresses"`
	AdministrativeState string `json:"administrative_state"`
	OperationalState    string `json:"operational_state"`
}

type Snapshot struct {
	Schema     int         `json:"schema"`
	ObservedAt time.Time   `json:"observed_at"`
	Interfaces []Interface `json:"interfaces"`
}

type Provider interface {
	Snapshot() (Snapshot, error)
}

type SystemProvider struct{}

func (SystemProvider) Snapshot() (Snapshot, error) {
	items, err := net.Interfaces()
	if err != nil {
		return Snapshot{}, err
	}
	out := make([]Interface, 0, len(items))
	for _, item := range items {
		addrs, err := item.Addrs()
		if err != nil {
			return Snapshot{}, err
		}
		addresses := make([]Address, 0, len(addrs))
		for _, addr := range addrs {
			addresses = append(addresses, Address{CIDR: addr.String()})
		}
		sort.Slice(addresses, func(i, j int) bool { return addresses[i].CIDR < addresses[j].CIDR })
		flags := flagsOf(item.Flags)
		operational := "down"
		if item.Flags&net.FlagUp != 0 {
			operational = "up"
		}
		out = append(out, Interface{
			ID: item.Name,
			Name: item.Name,
			Index: item.Index,
			MTU: item.MTU,
			MAC: item.HardwareAddr.String(),
			Flags: flags,
			Addresses: addresses,
			AdministrativeState: operational,
			OperationalState: operational,
		})
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].Index == out[j].Index { return out[i].Name < out[j].Name }
		return out[i].Index < out[j].Index
	})
	return Snapshot{Schema: SchemaVersion, ObservedAt: time.Now().UTC(), Interfaces: out}, nil
}

func flagsOf(flags net.Flags) []string {
	values := make([]string, 0, 6)
	pairs := []struct{ flag net.Flags; name string }{
		{net.FlagUp, "up"},
		{net.FlagBroadcast, "broadcast"},
		{net.FlagLoopback, "loopback"},
		{net.FlagPointToPoint, "point_to_point"},
		{net.FlagMulticast, "multicast"},
		{net.FlagRunning, "running"},
	}
	for _, pair := range pairs {
		if flags&pair.flag != 0 { values = append(values, pair.name) }
	}
	return values
}
