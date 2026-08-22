package operations

import (
	"testing"
	"time"
)

func TestIncidentsReturnsOnlyAbnormalTerminalOperationsNewestFirst(t *testing.T) {
	dir := t.TempDir()
	store, err := Open(dir)
	if err != nil {
		t.Fatal(err)
	}

	if _, err := store.Start("op-success", "rbac.user.create", "admin", "admin", "viewer"); err != nil {
		t.Fatal(err)
	}
	if _, err := store.Finish("op-success", StatusSucceeded, ""); err != nil {
		t.Fatal(err)
	}

	time.Sleep(time.Millisecond)
	if _, err := store.Start("op-failed", "rbac.user.create", "admin", "admin", "viewer"); err != nil {
		t.Fatal(err)
	}
	if _, err := store.Finish("op-failed", StatusFailed, "user_create_failed"); err != nil {
		t.Fatal(err)
	}

	time.Sleep(time.Millisecond)
	if _, err := store.Start("op-interrupted", "system.change", "admin", "admin", "host"); err != nil {
		t.Fatal(err)
	}

	recovered, err := Open(dir)
	if err != nil {
		t.Fatal(err)
	}
	incidents := recovered.Incidents(10)
	if len(incidents) != 2 {
		t.Fatalf("incidents=%+v", incidents)
	}
	if incidents[0].ID != "op-interrupted" || incidents[0].Status != StatusInterrupted || incidents[0].ErrorCode != "process_restarted" {
		t.Fatalf("unexpected newest incident: %+v", incidents[0])
	}
	if incidents[1].ID != "op-failed" || incidents[1].Status != StatusFailed || incidents[1].ErrorCode != "user_create_failed" {
		t.Fatalf("unexpected failed incident: %+v", incidents[1])
	}
	for _, incident := range incidents {
		if incident.ID == "op-success" || incident.Status == StatusSucceeded || incident.Status == StatusRunning {
			t.Fatalf("non-incident operation leaked: %+v", incident)
		}
	}

	bounded := recovered.Incidents(1)
	if len(bounded) != 1 || bounded[0].ID != "op-interrupted" {
		t.Fatalf("bounded incidents=%+v", bounded)
	}
}
