# GenRtmp

As part of my video streaming project, I needed a way to ingest live media streams from clients, and RTMP was a popular choice. Initially, I used an open-source RTMP server, but it was single-threaded when using its built-in analytics, which became a limitation. So, I built my own RTMP server in Elixir using **DynamicSupervisors**, **gen_tcp**, and **GenServer**. Each incoming RTMP connection spawns a GenServer process that manages the socket and tracks key events and metrics. This approach makes the server scalable and fault-tolerant.

The project is still under heavy development. Currently upson starting the application, **gen_tcp** listens for incoming sockets at port 1935(which is the default port for RTMP) in passive mode meaning(non blocking mode). When a new socket connection arrives, the socket supervision creates a **GenServer** for the socket connection and gen_tcp yields controls of the socket to the new socket handler which is the gen_server. This genserver then communicates with the RTMP client in the other end. This process is documented here **https://rtmp.veriskope.com/docs/spec/**. This gen_server based socket can act as server depending on the flow messages with the other end. 



