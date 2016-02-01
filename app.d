import std.math,
	   std.random,
	   std.typecons;

import gfm.logger,
	   gfm.sdl2,
	   gfm.opengl;

import test.drawer;

void main()
{
	int width = 1280;
	int height = 720;

	auto log = new ConsoleLogger();

	// load dynamic libraries
	auto sdl2 = new SDL2(log, SharedLibVersion(2, 0, 0));
	OpenGL gl = new OpenGL(log);

	// You have to initialize each SDL subsystem you want by hand
	sdl2.subSystemInit(SDL_INIT_VIDEO);
	sdl2.subSystemInit(SDL_INIT_EVENTS);

	SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3);
	SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 3);
	SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_CORE);

	// create an OpenGL-enabled SDL window
	auto window = new SDL2Window(sdl2,
								SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED,
								width, height, SDL_WINDOW_OPENGL);

	// reload OpenGL now that a context exists
	gl.reload();
	// redirect OpenGL output to our Logger
	gl.redirectDebugOutput();
	
	window.setTitle("World Driver Championship Viewer");

	GLProgram program = createShader(gl);

	auto test = new Drawer(gl, program);

	glPointSize(3.0);

	while(!sdl2.keyboard.isPressed(SDLK_ESCAPE) && !sdl2.wasQuitRequested())
	{
		glClearColor(0.1, 0.2, 0.4, 1);
		glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
		sdl2.processEvents();

		if (sdl2.keyboard.isPressed(SDLK_p))
		{
			test.drawPoints();
		}
		else
		{
			test.drawTriangles();
		}

		window.swapBuffers();
	}
}

private auto createShader(OpenGL opengl) {
	// create a shader program made of a single fragment shader
	string tunnelProgramSource =
		q{#version 330 core

		#if VERTEX_SHADER
		in vec3 position;
		void main()
		{
			gl_Position.xyz = position;
			gl_Position.w = 1.0;
		}
		#endif

		#if FRAGMENT_SHADER
		out vec3 color;

		void main()
		{
			color = vec3(0.95, 0.95, 1.0);
		}
		#endif
	};

	return new GLProgram(opengl, tunnelProgramSource);
}