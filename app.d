import std.math,
	std.conv,
	std.stdio,
	std.string,
	std.random,
	std.format,
	std.typecons,

	core.thread,

	gfm.logger,
	gfm.sdl2,
	gfm.math,
	gfm.opengl,

	wdc.car,
	wdc.binary,

	camera,
	timekeeper,
	test.drawer;

private
{
	int width = 1280;
	int height = 720;
	Binary binaryFile;
	string releaseVersion = "0.0.0 Feb 16 2016";
	SDL2Window window;
	bool windowVisible = false;

	OpenGL gl;
	GLProgram program;
	GLProgram normalsProgram;

	Car selectedCar;
}

void main(string[] args)
{
	writeln("World Driver Championship for N64 viewer");
	writeln("Created by jaytheham @ gmail.com");
	writeln("--------------------------------\n");

	binaryFile = getWDCBinary(args);

	auto conLogger = new ConsoleLogger();
	SDL2 sdl2 = new SDL2(conLogger, SharedLibVersion(2, 0, 0));
	gl = new OpenGL(conLogger);

	window = createSDLWindow(sdl2);
	window.setTitle("World Driver Championship Viewer");
	window.hide();

	// reload OpenGL now that a context exists
	gl.reload();
	glPointSize(3.0);
	glClearColor(0.1, 0.2, 0.4, 1);
	glEnable(GL_DEPTH_TEST);
	glDepthFunc(GL_LESS);
	auto mode = GL_LINE;
	glPolygonMode(GL_FRONT_AND_BACK, GL_FILL);
	// redirect OpenGL output to our Logger
	gl.redirectDebugOutput();

	program = createShader(gl);
	normalsProgram = createNormalShader(gl);

	Camera basicCamera = new Camera(gfm.math.radians(45f), cast(float)width / height);

	//auto test = new Drawer(gl, program);
	

	while(!sdl2.wasQuitRequested())
	{
		if (windowVisible)
		{
			TimeKeeper.startNewFrame();
			sdl2.processEvents();
			if (sdl2.keyboard.isPressed(SDLK_ESCAPE))
			{
				setWindowVisible(false);
				continue;
			}
			basicCamera.update(sdl2, TimeKeeper.getDeltaTime());
			
			glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

			if (sdl2.keyboard.testAndRelease(SDLK_n))
			{
				selectedCar.prevModelBlock();
			}
			if (sdl2.keyboard.testAndRelease(SDLK_m))
			{
				selectedCar.nextModelBlock();
			}
			if (sdl2.keyboard.testAndRelease(SDLK_j))
			{
				selectedCar.prevPalette();
			}
			if (sdl2.keyboard.testAndRelease(SDLK_k))
			{
				selectedCar.nextPalette();
			}

			if (sdl2.keyboard.testAndRelease(SDLK_p))
			{
				mode = mode == GL_FILL ? GL_LINE : GL_FILL;
				glPolygonMode(GL_FRONT_AND_BACK, mode);
			}

			//test.drawTriangles(basicCamera);
			selectedCar.draw(basicCamera);
			selectedCar.drawNormals(basicCamera, normalsProgram);

			window.swapBuffers();
			Thread.sleep(TimeKeeper.uSecsUntilNextFrame().usecs);
		}
		else
		{
			write("\nWaiting for input: ");
			string[] commands = readln().removechars("{}").split();
			if (commands.length > 0)
			{
				writeln(); 
				switch (commands[0])
				{
					case "-d":
						if (commands.length >= 2)
						{
							binaryFile.dumpCarData(parse!int(commands[1]));
						}
						else
						{
							writeln("You didn't specify an offset");
						}
						break;
					case "-dc":
					case "--display-car":
						if (commands.length >= 2)
						{
							displayCar(parse!int(commands[1]));
						}
						else
						{
							writeln("You didn't specify a car index");
						}
						break;
					
					case "-h":
					case "--help":
						writeHelp();
						break;

					case "-lc":
					case "--list-cars":
						listCars();
						break;

					case "-v":
					case "--version":
						writeln(releaseVersion);
						break;

					default:
						writeln("Unrecognised command, type -h or --help for a list of available commands");
						break;
				}
			}
		}
	}
}

private Binary getWDCBinary(string[] args)
{
	string binaryPath;
	if (args.length == 1)
	{
		writeln("Drag and drop a World Driver Championship ROM on the exe to load it.");
		writeln("Otherwise you can enter the unquoted path to a ROM and press Enter now:");
		binaryPath = chomp(readln());
	}
	else
	{
		binaryPath = args[1];
	}
	return new Binary(binaryPath);
}

private auto createSDLWindow(SDL2 sdl2)
{
	// You have to initialize each SDL subsystem you want by hand
	sdl2.subSystemInit(SDL_INIT_VIDEO);
	sdl2.subSystemInit(SDL_INIT_EVENTS);

	SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3);
	SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 3);
	SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_CORE);

	// create an OpenGL-enabled SDL window
	return new SDL2Window(sdl2, SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED,
								width, height, SDL_WINDOW_OPENGL);
}

private void setWindowVisible(bool isVisible)
{
	if (isVisible)
	{
		SDL_SetRelativeMouseMode(SDL_TRUE);
		window.show();
		windowVisible = true;
		TimeKeeper.start(60);
	}
	else
	{
		window.hide();
		SDL_SetRelativeMouseMode(SDL_FALSE);
		windowVisible = false;
	}
}

private auto createShader(OpenGL opengl)
{
	// create a shader program made of a single fragment shader
	string tunnelProgramSource =
		q{#version 330 core

		#if VERTEX_SHADER
		in ivec3 position;
		in vec2 vertexUV;
		in ivec3 inNormal;

		out vec2 UV;

		uniform mat4 mvpMatrix;
		void main()
		{
			gl_Position = mvpMatrix * vec4(position, 1.0);
			UV = vertexUV;
		}
		#endif

		#if FRAGMENT_SHADER
		in vec2 UV;
		out vec3 color;
		uniform sampler2D textureSampler;

		void main()
		{
			color = texture( textureSampler, UV ).rgb;
		}
		#endif
	};

	return new GLProgram(opengl, tunnelProgramSource);
}

private auto createNormalShader(OpenGL opengl)
{
	// create a shader program made of a single fragment shader
	string tunnelProgramSource =
		q{#version 330 core

		#if VERTEX_SHADER
		in ivec3 position;
		in vec2 vertexUV;
		in ivec3 inNormal;

		out ivec3 normalOut;

		void main()
		{
			gl_Position = vec4(position, 1.0);
			normalOut = inNormal;
		}
		#endif

		#if GEOMETRY_SHADER
		layout(triangles) in;
		layout(line_strip, max_vertices=6) out;

		uniform float normalsLength;
		uniform mat4 mvpMatrix;
		
		in flat ivec3 normalOut[];

		out vec4 vertex_color;

		void main()
		{
			for(int i = 0; i < gl_in.length(); i++)
		    {
			    vec3 P = gl_in[i].gl_Position.xyz;
				vec3 N = normalOut[i].xyz;

				gl_Position = mvpMatrix * vec4(P, 1.0);
				vertex_color = vec4(1,1,0.5,1);
				EmitVertex();

				gl_Position = mvpMatrix * vec4(P + N * normalsLength, 1.0);
				vertex_color = vec4(1,0,1,1);
				EmitVertex();

				EndPrimitive();
		    }
		}
		#endif

		#if FRAGMENT_SHADER
		in vec4 vertex_color;
		out vec4 Out_Color;
		void main()
		{
		 	Out_Color = vertex_color;
		}
		#endif
	};

	return new GLProgram(opengl, tunnelProgramSource);
}

private void listCars()
{
	writeln("\nIndex\tCar Name");
	writeln("-----\t--------\n");
	foreach(index, carName; binaryFile.getCarList()){
		writefln("%d\t%s", index, carName);
	}
}

private void displayCar(int index)
{
	selectedCar = binaryFile.getCar(index);
	selectedCar.enableDrawing(gl, program, normalsProgram);
	setWindowVisible(true);
	writefln("\nDisplaying car #%d", index);
	writeln("Press Escape to return to command window");
}

private void writeHelp()
{
	writeln("\nAvailable commands:");
	writeln("\t-dc {0}\t--display-car {0}\tDisplay car {0}");
	writeln("\t-h\t--help\t\t\tList commands");
	writeln("\t-lc\t--list-cars\t\tList cars in ROM");
	writeln("\t-v\t--version\t\tShow program version");
	writeln();
}