package privileged

import (
	"errors"
	"fmt"
)

const (
	ProtocolVersion = 1

	ErrorCodeInvalidRequest       = "invalid_request"
	ErrorCodePermissionDenied     = "permission_denied"
	ErrorCodeUnsupportedOperation = "unsupported_operation"
	ErrorCodeTimeout              = "timeout"
	ErrorCodeExecutionFailed      = "execution_failed"
	ErrorCodeProtocol             = "protocol_error"
)

type Envelope struct {
	Version int     `json:"version"`
	Request Request `json:"request"`
}

type ResponseEnvelope struct {
	Version int     `json:"version"`
	Result  Result  `json:"result"`
	Error   *Failure `json:"error,omitempty"`
}

type Failure struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

type RemoteError struct {
	Code    string
	Message string
}

func (e *RemoteError) Error() string {
	if e == nil {
		return ""
	}
	return fmt.Sprintf("privileged worker: %s: %s", e.Code, e.Message)
}

func failureFor(err error) *Failure {
	if err == nil {
		return nil
	}

	code := ErrorCodeExecutionFailed
	switch {
	case errors.Is(err, ErrInvalidRequest):
		code = ErrorCodeInvalidRequest
	case errors.Is(err, ErrPermissionDenied):
		code = ErrorCodePermissionDenied
	case errors.Is(err, ErrUnsupportedOperation):
		code = ErrorCodeUnsupportedOperation
	case errors.Is(err, ErrTimeout):
		code = ErrorCodeTimeout
	}

	return &Failure{Code: code, Message: err.Error()}
}
