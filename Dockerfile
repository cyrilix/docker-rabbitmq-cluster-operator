FROM --platform=$BUILDPLATFORM golang:1.16-alpine AS builder-src

ARG BUILDPLATFORM
ARG version="v1.8.1"

RUN apk add -U git


WORKDIR /workspace
RUN git clone https://github.com/rabbitmq/cluster-operator.git

WORKDIR /workspace/cluster-operator


RUN git checkout ${version}

RUN go mod download


# ---------------------------------------
FROM --platform=$BUILDPLATFORM builder-src AS builder

ARG TARGETPLATFORM
ARG BUILDPLATFORM

RUN GOOS=$(echo $TARGETPLATFORM | cut -f1 -d/) && \
    GOARCH=$(echo $TARGETPLATFORM | cut -f2 -d/) && \
    GOARM=$(echo $TARGETPLATFORM | cut -f3 -d/ | sed "s/v//" ) && \
    CGO_ENABLED=0 GOOS=${GOOS} GOARCH=${GOARCH} GOARM=${GOARM} go build -v -a -o manager main.go
    #CGO_ENABLED=0 GOOS=${GOOS} GOARCH=${GOARCH} GOARM=${GOARM} go build -v -a -tags timetzdata -o manager main.go


# ---------------------------------------
FROM alpine:latest as etc-builder

RUN echo "rabbitmq-cluster-operator:x:1000:" > /etc/group && \
    echo "rabbitmq-cluster-operator:x:1000:1000::/home/rabbitmq-cluster-operator:/usr/sbin/nologin" > /etc/passwd

RUN apk add -U --no-cache ca-certificates

# ---------------------------------------
FROM scratch

ARG GIT_COMMIT
LABEL GitCommit=$GIT_COMMIT

WORKDIR /
COPY --from=builder /workspace/cluster-operator/manager .
COPY --from=etc-builder /etc/passwd /etc/group /etc/
COPY --from=etc-builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt

USER 1000:1000

ENTRYPOINT ["/manager"]





