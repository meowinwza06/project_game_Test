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

state = "LOBBY" 
clients = [] 

# Game Constants
WIDTH = 800
HEIGHT = 450
FLOOR_Y = 450
BALL_RADIUS = 25  # เพิ่มขนาดลูกบอลจาก 15 เป็น 25
P_WIDTH = 80
P_HEIGHT = 100
NET_HEIGHT = 120
NET_WIDTH = 12

# Physics state
ball = {"x": WIDTH/2, "y": 50, "vx": 0, "vy": 0, "reset_timer": 0, "scored": False}
p1 = {"x": 80, "y": FLOOR_Y - P_HEIGHT/2, "score": 0, "w": P_WIDTH, "h": P_HEIGHT}
p2 = {"x": WIDTH - 80, "y": FLOOR_Y - P_HEIGHT/2, "score": 0, "w": P_WIDTH, "h": P_HEIGHT}
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
        except (BlockingIOError, Exception):
            break

    # Update Game State
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
        if ball_next_x - BALL_RADIUS < 0 or ball_next_x + BALL_RADIUS > WIDTH:
            ball["vx"] *= -0.8
            ball_next_x = ball["x"] # ป้องกันบอลทะลุ

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
        if ball_next_y + BALL_RADIUS > FLOOR_Y - NET_HEIGHT:
            if abs(ball_next_x - net_x) < (NET_WIDTH/2 + BALL_RADIUS):
                ball["vx"] *= -0.8
                ball_next_x = ball["x"]

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