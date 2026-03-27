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
bound_min_x = 0
bound_max_x = 1000

# Game Constants
WIDTH = 1000
HEIGHT = 500
FLOOR_Y = 500
BALL_RADIUS = 70
P_WIDTH = 120
P_HEIGHT = 260
NET_HEIGHT = 360
NET_WIDTH = 36

# Physics state
ball = {"x": WIDTH/2, "y": 50, "vx": 0, "vy": 0, "reset_timer": 0, "scored": False}
p1 = {"x": 150, "y": FLOOR_Y - P_HEIGHT/2, "score": 0, "w": P_WIDTH, "h": P_HEIGHT}
p2 = {"x": WIDTH - 150, "y": FLOOR_Y - P_HEIGHT/2, "score": 0, "w": P_WIDTH, "h": P_HEIGHT}
game_time = 90
last_time = time.time()

def reset_ball(scorer):
    ball["x"] = WIDTH/2
    ball["y"] = 50
    ball["vx"] = random.choice([-300, 300]) 
    ball["vy"] = -50
    ball["reset_timer"] = 0
    ball["scored"] = False

def send_to_all(msg_dict):
    try:
        msg_bytes = json.dumps(msg_dict).encode('utf-8')
        for c in clients:
            sock.sendto(msg_bytes, c)
    except Exception:
        pass

def check_collision(px, py, pw, ph, bx, by, br):
    closest_x = max(px - pw/2, min(bx, px + pw/2))
    closest_y = max(py - ph/2, min(by, py + ph/2))
    dx = bx - closest_x
    dy = by - closest_y
    return (dx**2 + dy**2) < (br**2)

while True:
    now = time.time()
    dt = now - last_time
    last_time = now

    # Process messages
    while True:
        try:
            data, addr = sock.recvfrom(1024)
            msg = json.loads(data.decode('utf-8'))
            
            if msg["type"] == "JOIN":
                if addr not in clients and len(clients) < 2:
                    clients.append(addr)
                    player_id = len(clients)
                    sock.sendto(json.dumps({"type": "ACCEPTED", "player_id": player_id}).encode('utf-8'), addr)
                    if len(clients) == 2:
                        state = "PLAYING"
                        game_time = 90
                        bound_min_x = msg.get("minX", 0)
                        bound_max_x = msg.get("maxX", WIDTH)
                        p1["score"], p2["score"] = 0, 0
                        reset_ball(1)
                        send_to_all({"type": "START", "time": game_time, "bg_num": random.randint(1,4), "bgm_num": random.randint(1,3)})
            
            elif msg["type"] == "FORCE_START" and state == "LOBBY":
                if addr in clients:
                    state = "PLAYING"
                    game_time = 90
                    bound_min_x = msg.get("minX", 0)
                    bound_max_x = msg.get("maxX", WIDTH)
                    p1["score"], p2["score"] = 0, 0
                    reset_ball(1)
                    send_to_all({"type": "START", "time": game_time, "bg_num": random.randint(1,4), "bgm_num": random.randint(1,3)})

            elif msg["type"] == "MOVE" and state == "PLAYING":
                if addr in clients:
                    pid = clients.index(addr) + 1
                    if pid == 1:
                        p1["x"], p1["y"] = msg.get("x", p1["x"]), msg.get("y", p1["y"])
                    elif pid == 2:
                        p2["x"], p2["y"] = msg.get("x", p2["x"]), msg.get("y", p2["y"])

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
        last_time = now  # keep resetting so dt doesn't accumulate
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
            
        if ball.get("reset_timer", 0) > 0:
            ball["reset_timer"] -= dt
            if ball["reset_timer"] <= 0:
                reset_ball(1)
        
        # --- Physics Loop (ต้องอยู่ตรงนี้เพื่อให้บอลขยับตลอด) ---
        ball_next_x = ball["x"] + ball["vx"] * dt
        ball_next_y = ball["y"] + ball["vy"] * dt
        ball["vy"] += 600 * dt # Gravity

        # Wall collisions
        if ball_next_x - BALL_RADIUS < bound_min_x:
            ball["vx"] *= -0.8
            ball_next_x = bound_min_x + BALL_RADIUS # ป้องกันบอลทะลุ
        elif ball_next_x + BALL_RADIUS > bound_max_x:
            ball["vx"] *= -0.8
            ball_next_x = bound_max_x - BALL_RADIUS # ป้องกันบอลทะลุ

        # Floor/Score
        if ball_next_y + BALL_RADIUS >= FLOOR_Y:
            ball_next_y = FLOOR_Y - BALL_RADIUS
            ball["vy"] *= -0.7
            if not ball["scored"]:
                ball["scored"] = True
                ball["reset_timer"] = 1.5
                if ball_next_x < WIDTH / 2: p2["score"] += 1
                else: p1["score"] += 1

        # Net collision
        net_x = WIDTH / 2
        net_top = FLOOR_Y - NET_HEIGHT
        net_y = FLOOR_Y - NET_HEIGHT / 2
        
        closest_x = max(net_x - NET_WIDTH/2, min(ball_next_x, net_x + NET_WIDTH/2))
        closest_y = max(net_top, min(ball_next_y, FLOOR_Y))
        
        c_dx = ball_next_x - closest_x
        c_dy = ball_next_y - closest_y
        dist_sq = c_dx**2 + c_dy**2
        
        if dist_sq < BALL_RADIUS**2:
            if dist_sq == 0:
                nx, ny, dist = 0, -1, 0.1
            else:
                dist = dist_sq ** 0.5
                nx, ny = c_dx / dist, c_dy / dist
                
            pen = BALL_RADIUS - dist
            ball_next_x += nx * pen
            ball_next_y += ny * pen
            
            dot = ball["vx"] * nx + ball["vy"] * ny
            if dot < 0:
                res = 0.75
                ball["vx"] -= (1 + res) * dot * nx
                ball["vy"] -= (1 + res) * dot * ny

        # Player collisions
        hit = False
        if check_collision(p1["x"], p1["y"], p1["w"], p1["h"], ball_next_x, ball_next_y, BALL_RADIUS):
            ball["vy"], ball["vx"] = -450, (ball_next_x - p1["x"]) * 7
            hit = True
        elif check_collision(p2["x"], p2["y"], p2["w"], p2["h"], ball_next_x, ball_next_y, BALL_RADIUS):
            ball["vy"], ball["vx"] = -450, (ball_next_x - p2["x"]) * 7
            hit = True
        
        if hit: send_to_all({"type": "HIT"})

        ball["x"], ball["y"] = ball_next_x, ball_next_y
        
        # Broadcast STATE
        send_to_all({
            "type": "STATE",
            "ball": {"x": int(ball["x"]), "y": int(ball["y"])},
            "p1": {"x": int(p1["x"]), "y": int(p1["y"]), "score": p1["score"]},
            "p2": {"x": int(p2["x"]), "y": int(p2["y"]), "score": p2["score"]},
            "time": int(game_time)
        })

    time.sleep(1/60)