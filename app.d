import std.math,
       std.random,
       std.typecons,
       testDrawer;

import std.experimental.logger;

import derelict.util.loader;

import gfm.logger,
       gfm.sdl2,
       gfm.opengl,
       gfm.math;

void main()
{
    int width = 1280;
    int height = 720;
    double ratio = width / cast(double)height;

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
                                    width, height,
                                    SDL_WINDOW_OPENGL);

    // reload OpenGL now that a context exists
    gl.reload();
    // redirect OpenGL output to our Logger
    gl.redirectDebugOutput();
	
	window.setTitle("World Driver Championship Viewer");

	auto program = createShader(gl);

	auto test = new testDrawer(gl, program);

    while(!sdl2.keyboard.isPressed(SDLK_ESCAPE) && !sdl2.wasQuitRequested())
    {
        sdl2.processEvents();

        test.draw();

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
            color = vec3(1,0.5,0);
        }
        #endif
    };

    return new GLProgram(opengl, tunnelProgramSource);
}