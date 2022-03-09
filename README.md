# docker-rabbitmq-cluster-operator

Multiarch docker images for [Rabbitmq Cluster Operator](https://github.com/rabbitmq/cluster-operator)

## Build

```sh
 docker buildx build . --platform linux/arm/7,linux/arm64,linux/amd64 -t cyrilix/rabbitmq-cluster-operator:1.11.1 --push
```
