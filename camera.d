
import std.math: sin, cos, PI;
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
		float speed = 700f;
		float mouseSpeed = 0.15f;
		float hRadians = -0.78f;
		float vRadians = -0.65f;
	}

	this(float fov, float ratio, float nearClip = 100f, float farClip = 50000.0f)
	{
		position = vec3f(1000, 1000, -1000);
		direction = vec3f(0, 0, 1);
		projection = mat4f.perspective(fov, ratio, nearClip, farClip);
		view = mat4f.identity();
	}

	public mat4f getPVM(mat4f model)
	{
		return projection * (view * model);
	}

	public void update(SDL2 sdl2, float deltaT)
	{
		static import gfm.math.vector;
		int deltaX = (sdl2.mouse.lastDeltaX() >= -2 && sdl2.mouse.lastDeltaX() <= 2) ? 0 : sdl2.mouse.lastDeltaX();
		int deltaY = (sdl2.mouse.lastDeltaY() >= -2 && sdl2.mouse.lastDeltaY() <= 2) ? 0 : sdl2.mouse.lastDeltaY();
		hRadians += mouseSpeed * deltaT * -deltaX;
		vRadians += mouseSpeed * deltaT * -deltaY;
		direction = [cos(vRadians) * sin(hRadians), sin(vRadians), cos(vRadians) * cos(hRadians)];
		right = [sin(hRadians - PI / 2), 0, cos(hRadians - PI / 2)];
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
			position += right * deltaT * speed * speedBoost;
		}
		if (sdl2.keyboard.isPressed(SDLK_a))
		{
			position -= right * deltaT * speed * speedBoost;
		}
		view = mat4f.lookAt(position, position + direction, up);
	}
}