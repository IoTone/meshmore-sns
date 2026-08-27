#!/bin/bash
set -e
ffmpeg -nostdin -y -v error \
  -i demo.mp4 -i demo1.mp4 -i demo2.mp4 -i demo3.mp4 -i meshmore-xr/store/cut/endcard.mp4 \
  -filter_complex "[3:v]trim=8.0:15.0,setpts=PTS-STARTPTS[v0];\
   [3:a]atrim=8.0:15.0,asetpts=PTS-STARTPTS[a0];\
   [1:v]trim=9.0:12.0,setpts=PTS-STARTPTS[v1];\
   [1:a]atrim=9.0:12.0,asetpts=PTS-STARTPTS[a1];\
   [0:v]trim=42.0:48.0,setpts=PTS-STARTPTS[v2];\
   [0:a]atrim=42.0:48.0,asetpts=PTS-STARTPTS[a2];\
   [0:v]trim=56.0:62.0,setpts=PTS-STARTPTS[v3];\
   [0:a]atrim=56.0:62.0,asetpts=PTS-STARTPTS[a3];\
   [0:v]trim=78.0:86.0,setpts=PTS-STARTPTS[v4];\
   [0:a]atrim=78.0:86.0,asetpts=PTS-STARTPTS[a4];\
   [2:v]trim=6.0:12.0,setpts=PTS-STARTPTS[v5];\
   [2:a]atrim=6.0:12.0,asetpts=PTS-STARTPTS[a5];\
   [3:v]trim=43.5:49.5,setpts=PTS-STARTPTS[v6];\
   [3:a]atrim=43.5:49.5,asetpts=PTS-STARTPTS[a6];\
   [3:v]trim=64.0:70.0,setpts=PTS-STARTPTS[v7];\
   [3:a]atrim=64.0:70.0,asetpts=PTS-STARTPTS[a7];\
   [4:v]trim=0.0:2.5,setpts=PTS-STARTPTS[v8];\
   [4:a]atrim=0.0:2.5,asetpts=PTS-STARTPTS[a8];\
   [v0][a0][v1][a1][v2][a2][v3][a3][v4][a4][v5][a5][v6][a6][v7][a7][v8][a8]concat=n=9:v=1:a=1[vc][ac];\
   [ac]loudnorm=I=-16:TP=-1.5:LRA=11[a];\
   [vc]format=yuv420p[v]" \
  -map "[v]" -map "[a]" -c:v libx264 -crf 18 -preset slow -r 36 \
  -c:a aac -b:a 192k -ar 48000 -movflags +faststart \
  meshmore-xr/store/cut/meshmore-xr-promo.mp4
echo "segments=9 target=50.5s"
