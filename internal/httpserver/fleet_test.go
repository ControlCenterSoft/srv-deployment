package httpserver

import (
	"encoding/json"
	"net/http"
	"strings"
	"testing"
)

func TestFleetInventoryCreateListAndViewerRBAC(t *testing.T) {
	app:=newTestApp(t); adminCookie,adminCSRF:=login(t,app,"admin",app.adminPassword)
	rr:=requestJSON(t,app.handler,http.MethodPost,"/api/v1/fleet/nodes",`{"name":"srv-01","address":"10.10.0.11","group":"office","environment":"production"}`,adminCookie,adminCSRF)
	if rr.Code!=http.StatusCreated || !strings.Contains(rr.Body.String(),`"status":"pending_enrollment"`) { t.Fatalf("create fleet node status=%d body=%s",rr.Code,rr.Body.String()) }
	rr=requestJSON(t,app.handler,http.MethodGet,"/api/v1/fleet/nodes","",adminCookie,""); if rr.Code!=http.StatusOK || !strings.Contains(rr.Body.String(),`"srv-01"`) { t.Fatalf("list status=%d body=%s",rr.Code,rr.Body.String()) }
	rr=requestJSON(t,app.handler,http.MethodPost,"/api/v1/rbac/users",`{"username":"fleetviewer","password":"fleetviewer-password-123","role":"viewer"}`,adminCookie,adminCSRF); if rr.Code!=http.StatusCreated { t.Fatalf("create viewer=%d %s",rr.Code,rr.Body.String()) }
	viewerCookie,viewerCSRF:=login(t,app,"fleetviewer","fleetviewer-password-123")
	rr=requestJSON(t,app.handler,http.MethodGet,"/api/v1/fleet/nodes","",viewerCookie,""); if rr.Code!=http.StatusOK { t.Fatalf("viewer fleet read=%d %s",rr.Code,rr.Body.String()) }
	rr=requestJSON(t,app.handler,http.MethodPost,"/api/v1/fleet/nodes",`{"name":"srv-02","address":"10.10.0.12"}`,viewerCookie,viewerCSRF); if rr.Code!=http.StatusForbidden { t.Fatalf("viewer fleet write=%d",rr.Code) }
	rr=requestJSON(t,app.handler,http.MethodPost,"/api/v1/fleet/nodes/srv-01/enrollment",`{}`,viewerCookie,viewerCSRF); if rr.Code!=http.StatusForbidden { t.Fatalf("viewer enrollment=%d",rr.Code) }
}

func TestFleetMutationRequiresCSRF(t *testing.T) {
	app:=newTestApp(t); adminCookie,_:=login(t,app,"admin",app.adminPassword)
	rr:=requestJSON(t,app.handler,http.MethodPost,"/api/v1/fleet/nodes",`{"name":"srv-01","address":"10.10.0.11"}`,adminCookie,""); if rr.Code!=http.StatusForbidden { t.Fatalf("missing csrf=%d",rr.Code) }
	rr=requestJSON(t,app.handler,http.MethodPost,"/api/v1/fleet/nodes/srv-01/enrollment",`{}`,adminCookie,""); if rr.Code!=http.StatusForbidden { t.Fatalf("missing enrollment csrf=%d",rr.Code) }
}

func TestFleetSecureEnrollmentHeartbeatAndHealth(t *testing.T) {
	app:=newTestApp(t); adminCookie,adminCSRF:=login(t,app,"admin",app.adminPassword)
	rr:=requestJSON(t,app.handler,http.MethodPost,"/api/v1/fleet/nodes",`{"name":"srv-01","address":"10.10.0.11"}`,adminCookie,adminCSRF); if rr.Code!=http.StatusCreated { t.Fatalf("create=%d %s",rr.Code,rr.Body.String()) }
	rr=requestJSON(t,app.handler,http.MethodPost,"/api/v1/fleet/nodes/srv-01/enrollment",`{}`,adminCookie,adminCSRF); if rr.Code!=http.StatusCreated { t.Fatalf("prepare=%d %s",rr.Code,rr.Body.String()) }
	var prepared struct{ Enrollment struct{ Token string `json:"token"` } `json:"enrollment"` }; if err:=json.Unmarshal(rr.Body.Bytes(),&prepared); err!=nil { t.Fatal(err) }; if prepared.Enrollment.Token=="" { t.Fatal("missing enrollment token") }
	body:=`{"node_id":"srv-01","token":"`+prepared.Enrollment.Token+`","agent_version":"1.1.8"}`
	rr=requestJSON(t,app.handler,http.MethodPost,"/api/v1/fleet/enroll",body,nil,""); if rr.Code!=http.StatusOK { t.Fatalf("enroll=%d %s",rr.Code,rr.Body.String()) }
	var enrolled struct{ AgentCredential string `json:"agent_credential"` }; if err:=json.Unmarshal(rr.Body.Bytes(),&enrolled); err!=nil { t.Fatal(err) }; if enrolled.AgentCredential=="" { t.Fatal("missing one-time agent credential") }
	if strings.Contains(rr.Body.String(),"agent_credential_hash") { t.Fatal("agent hash leaked") }

	heartbeat:=`{"node_id":"srv-01","agent_version":"1.1.9","hostname":"srv-01.example","os_name":"Ubuntu","os_version":"26.04","architecture":"amd64"}`
	rr=requestJSON(t,app.handler,http.MethodPost,"/api/v1/fleet/heartbeat",heartbeat,nil,""); if rr.Code!=http.StatusUnauthorized { t.Fatalf("heartbeat without bearer=%d %s",rr.Code,rr.Body.String()) }
	req:=newJSONRequest(t,http.MethodPost,"/api/v1/fleet/heartbeat",heartbeat); req.Header.Set("Authorization","Bearer "+enrolled.AgentCredential); rr=serveRequest(app.handler,req)
	if rr.Code!=http.StatusOK || !strings.Contains(rr.Body.String(),`"health":"healthy"`) { t.Fatalf("heartbeat=%d %s",rr.Code,rr.Body.String()) }

	rr=requestJSON(t,app.handler,http.MethodGet,"/api/v1/fleet/nodes","",adminCookie,"")
	for _,want:=range []string{`"healthy":1`,`"hostname":"srv-01.example"`,`"agent_version":"1.1.9"`,`"os_name":"Ubuntu"`,`"architecture":"amd64"`} { if !strings.Contains(rr.Body.String(),want) { t.Fatalf("fleet list missing %s: %s",want,rr.Body.String()) } }
	if strings.Contains(rr.Body.String(),"agent_credential_hash") || strings.Contains(rr.Body.String(),enrolled.AgentCredential) { t.Fatal("credential leaked in fleet list") }
}
