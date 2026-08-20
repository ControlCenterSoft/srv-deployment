//go:build linux

package privileged

import (
	"errors"
	"net"
	"syscall"
)

func peerUID(conn net.Conn) (int, error) {
	unixConn, ok := conn.(*net.UnixConn)
	if !ok {
		return -1, errors.New("connection is not unix")
	}
	raw, err := unixConn.SyscallConn()
	if err != nil {
		return -1, err
	}
	uid := -1
	var controlErr error
	if err := raw.Control(func(fd uintptr) {
		cred, err := syscall.GetsockoptUcred(int(fd), syscall.SOL_SOCKET, syscall.SO_PEERCRED)
		if err != nil {
			controlErr = err
			return
		}
		uid = int(cred.Uid)
	}); err != nil {
		return -1, err
	}
	if controlErr != nil {
		return -1, controlErr
	}
	return uid, nil
}
