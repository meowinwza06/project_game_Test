import socket
import json
import time
import random

HOST = '0.0.0.0'
PORT = 5555

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.bind((HOST, PORT))
sock.setblocking(False)

print(f"UDP Server up and listening on {HOST}:{PORT}")

state = "LOBBY"  # LOBBY / PLAYING / PAUSED / RESUMING / GAMEOVER
clients = []
resume_timer = 0

# Player state (only positions and scores; physics runs in client P1)
p1 = {"x": 150, "y": 430, "score": 0}
p2 = {"x": 850, "y": 430, "score": 0}
ball = {"x": 500, "y": 50}   # updated by P1 each frame via BALL_POS
game_time = 90
last_time = time.time()

def send_to_all(msg_dict):
    try:
        msg_bytes = json.dumps(msg_dict).encode('utf-8')
        for c in clients:
            sock.sendto(msg_bytes, c)
    except Exception:
        pass

while True:
    now = time.time()
    dt = now - last_time
    last_time = now

    # Process messages
    while True:
        try:
            data, addr = sock.recvfrom(2048)
            msg = json.loads(data.decode('utf-8'))

            if msg["type"] == "JOIN":
                if addr not in clients and len(clients) < 2:
                    clients.append(addr)
                    player_id = len(clients)
                    sock.sendto(json.dumps({"type": "ACCEPTED", "player_id": player_id}).encode('utf-8'), addr)
                    if len(clients) == 2:
                        state = "PLAYING"
                        game_time = 90
                        p1["score"], p2["score"] = 0, 0
                        ball["x"], ball["y"] = 500, 50
                        send_to_all({"type": "START", "time": game_time, "bg_num": random.randint(1,4), "bgm_num": random.randint(1,3)})

            elif msg["type"] == "FORCE_START" and state == "LOBBY":
                if addr in clients:
                    state = "PLAYING"
                    game_time = 90
                    p1["score"], p2["score"] = 0, 0
                    ball["x"], ball["y"] = 500, 50
                    send_to_all({"type": "START", "time": game_time, "bg_num": random.randint(1,4), "bgm_num": random.randint(1,3)})

            elif msg["type"] == "MOVE" and state in ("PLAYING", "PAUSED"):
                if addr in clients:
                    pid = clients.index(addr) + 1
                    if pid == 1:
                        p1["x"], p1["y"] = msg.get("x", p1["x"]), msg.get("y", p1["y"])
                    elif pid == 2:
                        p2["x"], p2["y"] = msg.get("x", p2["x"]), msg.get("y", p2["y"])

            elif msg["type"] == "BALL_POS" and state == "PLAYING":
                # Only P1 sends ball positions
                if addr in clients and clients.index(addr) == 0:
                    ball["x"] = msg.get("x", ball["x"])
                    ball["y"] = msg.get("y", ball["y"])

            elif msg["type"] == "SCORE" and state == "PLAYING":
                # P1 reports who scored
                if addr in clients and clients.index(addr) == 0:
                    scorer = msg.get("scorer", 0)
                    if scorer == 1:
                        p1["score"] += 1
                    elif scorer == 2:
                        p2["score"] += 1
                    # Tell clients to reset ball (P1 will restart local ball physics)
                    send_to_all({
                        "type": "SCORE_UPDATE",
                        "p1_score": p1["score"],
                        "p2_score": p2["score"],
                        "scorer": scorer
                    })

            elif msg["type"] == "PAUSE_REQUEST" and state == "PLAYING":
                if addr in clients:
                    other_idx = 1 - clients.index(addr)
                    if other_idx < len(clients):
                        sock.sendto(json.dumps({"type": "PAUSE_REQUEST"}).encode('utf-8'), clients[other_idx])

            elif msg["type"] == "PAUSE_RESPONSE" and state == "PLAYING":
                if addr in clients:
                    accept = msg.get("accept", False)
                    other_idx = 1 - clients.index(addr)
                    if accept:
                        state = "PAUSED"
                        send_to_all({"type": "PAUSED"})
                    else:
                        if other_idx < len(clients):
                            sock.sendto(json.dumps({"type": "PAUSE_DENIED"}).encode('utf-8'), clients[other_idx])

            elif msg["type"] == "RESUME" and state == "PAUSED":
                state = "RESUMING"
                resume_timer = 3.99
                sock.last_count = 3
                send_to_all({"type": "RESUME_COUNTDOWN", "count": 3})

        except (BlockingIOError, Exception):
            break

    # Update Game State
    if state == "RESUMING":
        resume_timer -= dt
        count = int(resume_timer)
        if count > 0 and count != getattr(sock, 'last_count', 0):
            send_to_all({"type": "RESUME_COUNTDOWN", "count": count})
            sock.last_count = count
        if resume_timer <= 0:
            state = "PLAYING"
            last_time = time.time()
            send_to_all({"type": "RESUMED"})
        else:
            last_time = now
            time.sleep(1/60)
            continue

    if state == "PAUSED":
        last_time = now
        time.sleep(1/60)
        continue

    if state == "PLAYING":
        game_time -= dt
        if game_time <= 0:
            state = "GAMEOVER"
            winner = 1 if p1["score"] > p2["score"] else (2 if p2["score"] > p1["score"] else 0)
            send_to_all({"type": "GAMEOVER", "winner": winner})
            clients = []
            continue

        # Broadcast state (ball position comes from P1 client)
        send_to_all({
            "type": "STATE",
            "ball": {"x": int(ball["x"]), "y": int(ball["y"])},
            "p1": {"x": int(p1["x"]), "y": int(p1["y"]), "score": p1["score"]},
            "p2": {"x": int(p2["x"]), "y": int(p2["y"]), "score": p2["score"]},
            "time": int(game_time)
        })

    time.sleep(1/60)