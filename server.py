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

state = "LOBBY" # LOBBY, PLAYING, GAMEOVER
clients = [] # list of (ip, port)

# Game Constants
WIDTH = 800
HEIGHT = 450
FLOOR_Y = 380
BALL_RADIUS = 15
P_WIDTH = 80
P_HEIGHT = 100
NET_HEIGHT = 120
NET_WIDTH = 12

# Physics state
ball = {"x": WIDTH/2, "y": 50, "vx": 0, "vy": 0, "reset_timer": 0}
p1 = {"x": 80, "y": FLOOR_Y - P_HEIGHT/2, "score": 0, "w": P_WIDTH, "h": P_HEIGHT}
p2 = {"x": WIDTH - 80, "y": FLOOR_Y - P_HEIGHT/2, "score": 0, "w": P_WIDTH, "h": P_HEIGHT}
game_time = 90
last_time = time.time()

def reset_ball(scorer):
    ball["x"] = WIDTH/2
    ball["y"] = 50
    # Randomly serve to a side
    ball["vx"] = random.choice([-300, 300]) # Faster serve
    ball["vy"] = -50
    ball["reset_timer"] = 0

def send_to_all(msg_dict):
    try:
        msg_bytes = json.dumps(msg_dict).encode('utf-8')
        for c in clients:
            sock.sendto(msg_bytes, c)
    except Exception as e:
        pass

def check_collision(px, py, pw, ph, bx, by, br):
    # px, py are center of player
    closest_x = max(px - pw/2, min(bx, px + pw/2))
    closest_y = max(py - ph/2, min(by, py + ph/2))
    dx = bx - closest_x
    dy = by - closest_y
    return (dx**2 + dy**2) < (br**2)

while True:
    now = time.time()
    dt = now - last_time
    last_time = now

    # Process incoming messages
    while True:
        try:
            data, addr = sock.recvfrom(1024)
            msg = json.loads(data.decode('utf-8'))
            
            if msg["type"] == "JOIN":
                if addr not in clients and len(clients) < 2:
                    clients.append(addr)
                    player_id = len(clients)
                    sock.sendto(json.dumps({"type": "ACCEPTED", "player_id": player_id}).encode('utf-8'), addr)
                    print(f"Client {addr} joined as Player {player_id}")
                    
                    if len(clients) == 2:
                        state = "PLAYING"
                        game_time = 90
                        p1["score"] = 0
                        p2["score"] = 0
                        bg_num = random.randint(1, 4)
                        reset_ball(1)
                        send_to_all({"type": "START", "time": game_time, "bg_num": bg_num})
                        print("Game Started!")
            
            elif msg["type"] == "MOVE" and state == "PLAYING":
                if addr in clients:
                    pid = clients.index(addr) + 1
                    if pid == 1:
                        p1["x"] = msg.get("x", p1["x"])
                        p1["y"] = msg.get("y", p1["y"])
                    elif pid == 2:
                        p2["x"] = msg.get("x", p2["x"])
                        p2["y"] = msg.get("y", p2["y"])
        except BlockingIOError:
            break
        except Exception as e:
            # ignore decoding errors or non-json packets
            break

    # Update Game State
    if state == "PLAYING":
        game_time -= dt
        if game_time <= 0:
            state = "GAMEOVER"
            winner = 1 if p1["score"] > p2["score"] else (2 if p2["score"] > p1["score"] else 0)
            send_to_all({"type": "GAMEOVER", "winner": winner})
            clients = [] # Reset lobby
            print(f"Game Over! Winner: Player {winner}")
        elif ball.get("reset_timer", 0) > 0:
            ball["reset_timer"] -= dt
            if ball["reset_timer"] <= 0:
                reset_ball(1) # scrorer is ignored now
            
            # Broadcast state holding steady
            state_msg = {
                "type": "STATE",
                "ball": {"x": int(ball["x"]), "y": int(ball["y"])},
                "p1": {"x": int(p1["x"]), "y": int(p1["y"]), "score": p1["score"]},
                "p2": {"x": int(p2["x"]), "y": int(p2["y"]), "score": p2["score"]},
                "time": int(game_time)
            }
            send_to_all(state_msg)
            time.sleep(1/60)
            continue
        else:
            # Update ball physics
            ball_next_x = ball["x"] + ball["vx"] * dt
            ball_next_y = ball["y"] + ball["vy"] * dt
            
            # Apply gravity
            ball["vy"] += 500 * dt
            
            # Wall collisions
            if ball_next_x - BALL_RADIUS < 0:
                ball_next_x = BALL_RADIUS
                ball["vx"] *= -0.8
            elif ball_next_x + BALL_RADIUS > WIDTH:
                ball_next_x = WIDTH - BALL_RADIUS
                ball["vx"] *= -0.8
                
            # Floor collision (Scoring)
            if ball_next_y + BALL_RADIUS >= FLOOR_Y:
                ball["x"] = ball_next_x
                ball["y"] = FLOOR_Y - BALL_RADIUS # Rest it on the ground visually
                ball["vx"] = 0
                ball["vy"] = 0
                ball["reset_timer"] = 1.0 # 1 second delay
                
                if ball_next_x < WIDTH / 2:
                    p2["score"] += 1
                else:
                    p1["score"] += 1
                continue

            # Ceiling collision
            if ball_next_y - BALL_RADIUS < 0:
                ball_next_y = BALL_RADIUS
                ball["vy"] *= -0.8

            # Net collision (middle)
            net_x_center = WIDTH / 2
            net_top_y = FLOOR_Y - NET_HEIGHT
            
            if ball_next_y + BALL_RADIUS > net_top_y:
                if (ball["x"] - net_x_center <= 0 and ball_next_x + BALL_RADIUS >= net_x_center - NET_WIDTH/2):
                    ball_next_x = net_x_center - NET_WIDTH/2 - BALL_RADIUS
                    ball["vx"] *= -0.8
                elif (ball["x"] - net_x_center >= 0 and ball_next_x - BALL_RADIUS <= net_x_center + NET_WIDTH/2):
                    ball_next_x = net_x_center + NET_WIDTH/2 + BALL_RADIUS
                    ball["vx"] *= -0.8
                elif (ball_next_y + BALL_RADIUS > net_top_y and ball_next_y - ball["vy"]*dt + BALL_RADIUS <= net_top_y):
                    # Hit top of net
                    if abs(ball_next_x - net_x_center) <= NET_WIDTH/2:
                        ball_next_y = net_top_y - BALL_RADIUS
                        ball["vy"] *= -0.8

            # Player collisions
            if check_collision(p1["x"], p1["y"], p1["w"], p1["h"], ball_next_x, ball_next_y, BALL_RADIUS):
                ball["vy"] = -450 # Bounce up
                ball["vx"] = (ball_next_x - p1["x"]) * 6 # Spin
                # Don't let it stick
                if ball_next_y > p1["y"] - p1["h"]/2 - BALL_RADIUS:
                    ball_next_y = p1["y"] - p1["h"]/2 - BALL_RADIUS
            elif check_collision(p2["x"], p2["y"], p2["w"], p2["h"], ball_next_x, ball_next_y, BALL_RADIUS):
                ball["vy"] = -450 # Bounce up
                ball["vx"] = (ball_next_x - p2["x"]) * 6 # Spin
                if ball_next_y > p2["y"] - p2["h"]/2 - BALL_RADIUS:
                    ball_next_y = p2["y"] - p2["h"]/2 - BALL_RADIUS
            
            # Update position
            ball["x"] = ball_next_x
            ball["y"] = ball_next_y

            # Broadcast state
            state_msg = {
                "type": "STATE",
                "ball": {"x": int(ball["x"]), "y": int(ball["y"])},
                "p1": {"x": int(p1["x"]), "y": int(p1["y"]), "score": p1["score"]},
                "p2": {"x": int(p2["x"]), "y": int(p2["y"]), "score": p2["score"]},
                "time": int(game_time)
            }
            send_to_all(state_msg)

    # Run at ~60 FPS
    time.sleep(1/60)
