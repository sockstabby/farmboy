# Introduction

Farmboy is a distributed and scalable task runner. This is originally intended to be used to collect thousands of datapoints from an external API on a schedule.

The project is split up into three repos.

Farmboy - is an Elixir OTP Genserver that is reponsible for discovering workers in a cluster. It uses the Quantum Elixir module to schedule tasks. It distibutes the work by choosing a node with the least load average. It invokes a Farmboy task by passing it the configuration whenever it is scheduled to run.

Farmboy Task - is the task that you define. This repo provides a sample implementation. Tasks can publish status messages which in turn get written to a Phoenix channel so end users can see the logs in realtime.

Farmboy Web - A user interface, webserver and API to configure tasks and get task status and logs.

Take a look at the in app screenshots in the Web app repo's [appscreens](https://github.com/sockstabby/farmboyweb/tree/master/appscreens) folder.

# Building

You have several options to build this code

1. Run a debug build

   ```
   iex --name router@127.0.0.1 --cookie asdf -S mix
   ```

   Note this has no dependency on the the task. Tasks can be loaded at any time
   and are detected when they join the cluster.

2. You can run a production release to run in docker or kubernetes.

   ```
   docker build . -t routerimage
   docker tag routerimage {docker-hub-username}/{default-repo-folder-name}:routerimage
   docker push {docker-hub-username}/{default-repo-folder-name}:routerimage

   ```

   Now it will be availabe to create containers in your Kubernetes
   cluster. See the router_dep.yaml file in Kubs repo for an example of how it gets referenced.

# Interesting notes on the implementation.

This app tracks the PIDS and reference returned from monitor

```
oldpid = spawn(fn -> 1 + 2 end)
#PID<0.111.0>
iex(10)> pid = spawn(fn -> 1 + 2 end)
#PID<0.119.0>
iex(11)> Process.monitor(pid)
#Reference<0.109932022.3302227970.196886>
iex(15)> flush()
{:DOWN, #Reference<0.109932022.3302227970.196886>, :process, #PID<0.119.0>,
:noproc}
:ok
iex(16)> flush()
:ok
iex(17)> Process.monitor(oldpid)
#Reference<0.109932022.3302227970.196940>
iex(18)> flush()
{:DOWN, #Reference<0.109932022.3302227970.196940>, :process, #PID<0.111.0>,
:noproc}
:ok
```
