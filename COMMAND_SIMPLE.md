```shell
$ docker rm $(docker ps -a -q) || 1
$ docker image rm $(docker images -q) || 1
$ docker build 
```

```shell
$ docker compose -f docker-compose.dev.yml --env-file .env up -d --build
```

```shell
$ docker pull mongo
$ docker pull postgres
$ docker pull prom/prometheus
$ docker pull prom/alertmanager
$ docker pull grafana/grafana
$ docker pull maildev/maildev
```

```shell
$ docker swarm init --advertise-addr eth0
$ docker node ls
$ docker node update --label-add db=true docker-desktop
$ docker stack deploy -c stack.local.yml shop-dunn
$ docker service update --force
```