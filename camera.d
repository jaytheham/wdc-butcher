
import std.math;
import gfm.math,
	   gfm.sdl2;

class Camera
{
	private
	{
		mat4f projection;
		mat4f view;
		vec3f position;
		vec3f direction;
		vec3f right;
		vec3f up;
		float speed = 4f;
		float mouseSpeed = 0.15f;
		float hAngle = 0f;
		float vAngle = -0.45f;
	}

	this(float fov, float ratio, float nearClip = 0.1f, float farClip = 100.0f)
	{
		position = vec3f(0, 5, -10);
		direction = vec3f(0, 0, 1);
		projection = mat4f.perspective(fov, ratio, nearClip, farClip);
		view = mat4f.lookAt(position, vec3f(0, 0, 0,), vec3f(0, 1, 0));
	}

	public mat4f getPVM(mat4f model)
	{
		return projection * (view * model);
	}

	public void update(SDL2 sdl2, float deltaT)
	{
		int deltaX = (sdl2.mouse.lastDeltaX() >= -2 && sdl2.mouse.lastDeltaX() <= 2) ? 0 : sdl2.mouse.lastDeltaX();
		int deltaY = (sdl2.mouse.lastDeltaY() >= -2 && sdl2.mouse.lastDeltaY() <= 2) ? 0 : sdl2.mouse.lastDeltaY();
		hAngle += mouseSpeed * deltaT * -deltaX;
		vAngle += mouseSpeed * deltaT * -deltaY;
		direction = [cos(vAngle) * sin(hAngle), sin(vAngle), cos(vAngle) * cos(hAngle)];
		right = [sin(hAngle - PI / 2), 0, cos(hAngle - PI / 2)];
		up = gfm.math.vector.cross(right, direction);

		float speedBoost = sdl2.keyboard.isPressed(SDLK_LSHIFT) ? 5f : 1f;
		
		if (sdl2.keyboard.isPressed(SDLK_w))
		{
			position += direction * deltaT * speed * speedBoost;
		}
		if (sdl2.keyboard.isPressed(SDLK_s))
		{
			position -= direction * deltaT * speed * speedBoost;
		}
		if (sdl2.keyboard.isPressed(SDLK_d))
		{
			position += right * deltaT * speed;
		}
		if (sdl2.keyboard.isPressed(SDLK_a))
		{
			position -= right * deltaT * speed;
		}
		view = mat4f.lookAt(position, position + direction, up);
	}
}