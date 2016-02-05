import std.math,
	   core.thread,
	   std.random,
	   std.format,
	   std.typecons;

import gfm.logger,
	   gfm.sdl2,
	   gfm.math,
	   gfm.opengl;

import camera,
	   timekeeper,
	   test.drawer;

private
{
	int width = 1280;
	int height = 720;
}

void main()
{
	auto conLogger = new ConsoleLogger();
	SDL2 sdl2 = new SDL2(conLogger, SharedLibVersion(2, 0, 0));
	OpenGL gl = new OpenGL(conLogger);

	auto window = createSDLWindow(sdl2);
	window.setTitle("World Driver Championship Viewer");

	// reload OpenGL now that a context exists
	gl.reload();
	glPointSize(3.0);
	glClearColor(0.1, 0.2, 0.4, 1);
	// redirect OpenGL output to our Logger
	gl.redirectDebugOutput();

	GLProgram program = createShader(gl);

	Camera basicCamera = new Camera(gfm.math.radians(45f), width / height);

	auto test = new Drawer(gl, program);	

	TimeKeeper.start(60);

	while(!sdl2.keyboard.isPressed(SDLK_ESCAPE) && !sdl2.wasQuitRequested())
	{
		TimeKeeper.startNewFrame();
		window.setTitle(format("World Driver Championship Viewer %.1f", 1/TimeKeeper.getDeltaTime()));
		sdl2.processEvents();
		basicCamera.update(sdl2, TimeKeeper.getDeltaTime());
		
		glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

		if (sdl2.keyboard.isPressed(SDLK_p))
		{
			test.drawPoints();
		}
		else
		{
			test.drawTriangles(basicCamera);
		}

		window.swapBuffers();
		Thread.sleep(TimeKeeper.uSecsUntilNextFrame().usecs);
	}
}

private auto createSDLWindow(SDL2 sdl2) {
	// You have to initialize each SDL subsystem you want by hand
	sdl2.subSystemInit(SDL_INIT_VIDEO);
	sdl2.subSystemInit(SDL_INIT_EVENTS);

	SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3);
	SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 3);
	SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_CORE);
	SDL_SetRelativeMouseMode(SDL_TRUE);

	// create an OpenGL-enabled SDL window
	return new SDL2Window(sdl2, SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED,
								width, height, SDL_WINDOW_OPENGL);
}

private auto createShader(OpenGL opengl)
{
	// create a shader program made of a single fragment shader
	string tunnelProgramSource =
		q{#version 330 core

		#if VERTEX_SHADER
		in vec3 position;
		uniform mat4 mvpMatrix;
		void main()
		{
			gl_Position = mvpMatrix * vec4(position, 1.0);
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