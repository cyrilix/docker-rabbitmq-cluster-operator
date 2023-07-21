#! /bin/bash

VERSION=2.4.0
IMAGE_SRC_NAME=cluster-operator-src
IMAGE_BUILDER_NAME=cluster-operator-builder
IMAGE_ETC_BUILDER_NAME=cluster-operator-etc-builder
MANIFEST_NAME=rabbitmq-cluster-operator

GREEN=""
BLANK=""
to_remove(){

buildah bud --platform linux/amd64 --build-arg version=v$VERSION --manifest rabbitmq-cluster-operator:$VERSION -f Dockerfile .
buildah bud --platform linux/arm64 --build-arg version=v$VERSION --manifest rabbitmq-cluster-operator:$VERSION -f Dockerfile .
buildah bud --platform linux/arm/v7 --build-arg version=v$VERSION --manifest rabbitmq-cluster-operator:$VERSION -f Dockerfile .

buildah push --all --rm -f v2s2 localhost/rabbitmq-cluster-operator:$VERSION docker://docker.io/cyrilix/rabbitmq-cluster-operator:$VERSION
}

build_src_image() {
  printf "${GREEN}Fetch source %s ${BLANK}\n\n" ${VERSION}

  local containerSrcName=rabbitmq-cluster-src

  buildah --name "$containerSrcName" from docker.io/golang:1.20-alpine

  buildah run "$containerSrcName" apk add -U git

  buildah config --workingdir /workspace "$containerSrcName"
  buildah run "$containerSrcName" git clone https://github.com/rabbitmq/cluster-operator.git

  buildah config --workingdir /workspace/cluster-operator "$containerSrcName"
  buildah run "$containerSrcName" git checkout "v${VERSION}"

  printf "\nDownload go dependencies\n"
  buildah run "$containerSrcName" go mod download

  printf "\nCommit image src as %s\n" "${IMAGE_SRC_NAME}:${VERSION}"
  buildah commit --rm "${containerSrcName}" "${IMAGE_SRC_NAME}:${VERSION}"

}

build_builder_image() {
  printf "${GREEN}\n\nBuild go manager${BLANK}\n\n"

  local containerBuilderName=rabbitmq-cluster-builder

  buildah --name "$containerBuilderName" from "${IMAGE_SRC_NAME}:${VERSION}"

  for TARGETPLATFORM in "linux/arm/v7" "linux/arm64" "linux/amd64"
  do
    printf "\nBuild manager for %s\n" $TARGETPLATFORM

    GOOS=$(echo $TARGETPLATFORM | cut -f1 -d/)
    GOARCH=$(echo $TARGETPLATFORM | cut -f2 -d/)
    GOARM=$(echo $TARGETPLATFORM | cut -f3 -d/ | sed "s/v//" )

    if [ -z "$GOARM" ]
    then
      buildah run \
        --env CGO_ENABLED=0 \
        --env GOOS="${GOOS}" \
        --env GOARCH="${GOARCH}" \
        ${containerBuilderName} \
        go build -a -o "manager.${GOARCH}" main.go
    else
      unset GOARM
      buildah run \
        --env CGO_ENABLED=0 \
        --env GOOS="${GOOS}" \
        --env GOARCH="${GOARCH}" \
        --env GOARM="${GOARM}" \
        ${containerBuilderName} \
        go build -a -o "manager.${GOARCH}" main.go
    fi
  done

  printf "Commit binary image as %s\n" "${IMAGE_BUILDER_NAME}:${VERSION}"
  buildah commit --rm "${containerBuilderName}" "${IMAGE_BUILDER_NAME}:${VERSION}"

}

build_etc_builder() {
  printf "${GREEN}\n\nBuild etc and certificates resources${BLANK}\n\n"

  local containerName=rabbitmq-cluster-etc-builder

  buildah --name "$containerName" from docker.io/alpine:latest

  buildah run "${containerName}" echo "rabbitmq-cluster-operator:x:1000:" \> /etc/group \; \
                                 echo "rabbitmq-cluster-operator:x:1000:1000::/home/rabbitmq-cluster-operator:/usr/sbin/nologin" \> /etc/passwd

  buildah run "${containerName}" apk add -U --no-cache ca-certificates

  printf "Commit certificates image as %s\n" "${IMAGE_ETC_BUILDER_NAME}:${VERSION}"
  buildah commit --rm "${containerName}" "${IMAGE_ETC_BUILDER_NAME}"
}

build_image() {
  printf "${GREEN}\n\nBuild final image${BLANK}\n\n"

  for TARGETPLATFORM in "linux/arm/v7" "linux/arm64" "linux/amd64"
  do
    printf "\nBuild for %s\n" $TARGETPLATFORM
    GOOS=$(echo $TARGETPLATFORM | cut -f1 -d/) && \
    GOARCH=$(echo $TARGETPLATFORM | cut -f2 -d/) && \
    GOARM=$(echo $TARGETPLATFORM | cut -f3 -d/ | sed "s/v//" ) && \

    VARIANT="--variant $(echo "${TARGETPLATFORM}" | cut -f3 -d/  )"
    if [[ -z "$GOARM" ]] ;
    then
      VARIANT=""
    fi

    local containerName=rabbitmq-cluster-builder-${GOARCH}

    buildah from --name "$containerName" --os "${GOOS}" --arch "${GOARCH}" ${VARIANT} scratch

    buildah config --workingdir / "$containerName"

    buildah copy --from "${IMAGE_BUILDER_NAME}:${VERSION}" "$containerName" /workspace/cluster-operator/manager.${GOARCH} /manager

    buildah copy --from="${IMAGE_ETC_BUILDER_NAME}" "$containerName" /etc/passwd /etc/group /etc/
    buildah copy --from="${IMAGE_ETC_BUILDER_NAME}" "$containerName" /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt

    buildah config --user 1000:1000 "${containerName}"
    buildah config --entrypoint '[ "/manager" ]' "${containerName}"

    printf "Commit final image manifest as %s\n" "${MANIFEST_NAME}:${VERSION}"
    buildah commit --rm  --manifest "${MANIFEST_NAME}:${VERSION}" "${containerName}"
  done
}

build_src_image
build_builder_image
build_etc_builder
build_image

buildah manifest push --rm --all -f v2s2 localhost/${MANIFEST_NAME}:${VERSION} docker://docker.io/cyrilix/${MANIFEST_NAME}:${VERSION}
