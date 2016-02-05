
import std.conv,
	   std.math;
import gfm.math,
	   gfm.sdl2,
	   gfm.opengl;

class Camera
{
	private
	{
		//Matrix!(float, 4, 4)
		mat4f projection;
		mat4f view;
		vec4f position;
		float radiansStep = 0.001f;
	}

	this(float fov, float ratio, float nearClip = 0.1f, float farClip = 100.0f)
	{
		position = [0f, 0f, -10f, 1f];
		projection = mat4f.perspective(fov, ratio, nearClip, farClip);
		view = mat4f.lookAt(vec3f(position[0], position[1], position[2]), vec3f(0, 0, 0,), vec3f(0, 1, 0));
	}

	public mat4f getPVM(mat4f model)
	{
		return projection * (view * model);
	}

	public void update(SDL2 sdl2)
	{
		float modifier = 0f;
		if (sdl2.keyboard.isPressed(SDLK_LEFT) && !sdl2.keyboard.isPressed(SDLK_RIGHT))
		{
			modifier = -1f;
		}
		else if (sdl2.keyboard.isPressed(SDLK_RIGHT) && !sdl2.keyboard.isPressed(SDLK_LEFT))
		{
			modifier = 1f;
		}

		mat4f rotationMatrix = mat4f.rotation(modifier * radiansStep, vec3f(0, 1, 0,));
		position = rotationMatrix * position;
		view = mat4f.lookAt(vec3f(position[0], position[1], position[2]), vec3f(0, 0, 0,), vec3f(0, 1, 0));
	}
}