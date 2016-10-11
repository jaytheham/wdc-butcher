import std.math,
	std.conv,
	std.stdio,
	std.file,
	std.string,
	std.random,
	std.format,
	std.zlib,
	std.typecons,

	core.thread,

	gfm.logger,
	gfm.sdl2,
	gfm.math,
	gfm.opengl,

	wdc.car,
	wdc.track,
	wdc.drawable,
	wdc.binary,

	camera,
	timekeeper,
	test.drawer;

private
{
	enum int WINDOW_WIDTH = 1280;
	enum int WINDOW_HEIGHT = 720;
	enum string RELEASE_VERSION = "0.0.0 Feb 16 2016";

	Binary binaryFile;
	SDL2Window window;
	bool windowVisible = false;

	int mode;

	OpenGL gl;

	Drawable selectedObject;

	struct UserCommand
	{
		string shortCommand;
		string longCommand;
		string description;
		string usage;
		bool function(string[] args) run;
	}
	UserCommand[] commands;
}

void testing()
{
	foreach (i, carname; binaryFile.getCarList())
	{
		writeln(carname);
		binaryFile.getCar(i);
	}
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

	setOpenGLState();

	//testing();

	Camera basicCamera = new Camera(gfm.math.radians(45f), cast(float)WINDOW_WIDTH / WINDOW_HEIGHT);
	setupCommands();

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

			glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

			basicCamera.update(sdl2, TimeKeeper.getDeltaTime());

			handleInput(sdl2);

			//test.drawTriangles(basicCamera);
			selectedObject.draw(basicCamera, getKeys(sdl2));

			window.swapBuffers();
			Thread.sleep(TimeKeeper.uSecsUntilNextFrame().usecs);
		}
		else
		{
			handleCommands();
		}
	}
}

private char[] getKeys(SDL2 sdl2)
{
	char[] keys;
	if (sdl2.keyboard.testAndRelease(SDLK_1))
	{
		keys ~= '1';
	}
	if (sdl2.keyboard.testAndRelease(SDLK_2))
	{
		keys ~= '2';
	}
	if (sdl2.keyboard.testAndRelease(SDLK_3))
	{
		keys ~= '3';
	}
	if (sdl2.keyboard.testAndRelease(SDLK_4))
	{
		keys ~= '4';
	}
	return keys;
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
								WINDOW_WIDTH, WINDOW_HEIGHT, SDL_WINDOW_OPENGL);
}

private void handleCommands()
{
	std.stdio.write("\nWaiting for input: ");
	string[] args = readln().removechars("{}").split();
	if (args.length > 0)
	{
		writeln();
		foreach(cmd; commands)
		{
			if (cmd.shortCommand == args[0] || cmd.longCommand == args[0])
			{
				if (!cmd.run(args))
				{
					writeln(cmd.usage);
				}
				return;
			}
		}
		writeHelp(null);
	}
}

private void handleInput(SDL2 sdl2)
{
	if (sdl2.keyboard.testAndRelease(SDLK_p))
	{
		mode = mode == GL_FILL ? GL_LINE : GL_FILL;
		glPolygonMode(GL_FRONT_AND_BACK, mode);
		if (mode == GL_LINE)
		{
			glDisable(GL_CULL_FACE);
		}
		else
		{
			glEnable(GL_CULL_FACE);
		}
	}
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

private void setOpenGLState()
{
	// reload OpenGL now that a context exists
	gl.reload();
	mode = GL_LINE;
	glPointSize(3.0);
	glClearColor(0.1, 0.2, 0.4, 1);
	glEnable(GL_DEPTH_TEST);
	glDepthFunc(GL_LESS);
	glPolygonMode(GL_FRONT_AND_BACK, GL_FILL);
	glEnable(GL_CULL_FACE);
	glCullFace(GL_BACK);
	glEnable(GL_BLEND);
	glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
	// redirect OpenGL output to our Logger
	gl.redirectDebugOutput();
}

private bool listCars(string[] args)
{
	writeln("\nIndex\tCar Name");
	writeln("-----\t--------\n");
	foreach(index, carName; binaryFile.getCarList()){
		writefln("%d\t%s", index, carName);
	}
	return true;
}

private void displayCar(int index)
{
	selectedObject = binaryFile.getCar(index);
	selectedObject.setupDrawing(gl);
	setWindowVisible(true);
	writefln("\nDisplaying car #%d", index);
	writeln("Press Escape to return to command window");
}

private bool extractCarObj(string[] args)
{
	try
	{
		int carIndex = parse!int(args[1]);
		binaryFile.getCar(carIndex).outputWavefrontObj();
		writefln("Car %d extracted to .obj file.", carIndex);
	}
	catch (ConvException e)
	{
		writeln(e.msg);
		return false;
	}
	return true;
}

private bool importCarObj(string[] args)
{
	try
	{
		selectedObject = new Car(args[1]);
	}
	catch (Exception e)
	{
		writeln(e.msg);
		return false;
	}
	return true;
}

private bool listTracks(string[] args)
{
	writeln("\nIndex\tTrack Name");
	writeln("-----\t--------\n");
	foreach(index, trackName; binaryFile.getTrackList()){
		writefln("%d\t%s", index, trackName);
	}
	return true;
}

private void displayTrack(int index, int variation)
{
	try
	{
		selectedObject = binaryFile.getTrack(index, variation);
	}
	catch (Exception e)
	{
		writeln(e.msg);
		return;
	}
	selectedObject.setupDrawing(gl);
	setWindowVisible(true);
	writefln("\nDisplaying track #%d variation %d", index, variation);
	writeln("Press Escape to return to command window");
}

private bool writeHelp(string[] args)
{
	writeln("\nAvailable commands:");
	foreach(cmd; commands)
	{
		writefln("\t%s\t%s\t\t%s", cmd.shortCommand, cmd.longCommand, cmd.description);
	}
	writeln();
	return true;
}

private void setupCommands()
{
	commands ~= UserCommand("lc", "list-cars", "List car names and indices", "lc", &listCars);
	commands ~= UserCommand("lt", "list-tracks", "List track names and indices", "lt", &listTracks);
	commands ~= UserCommand("dc", "display-car", "Display car {index}", "dc {intCarIndex}",
		(string[] args) {
			if (args.length == 2)
			{
				try
				{
					displayCar(parse!int(args[1]));
				}
				catch (ConvException e)
				{
					writeln(e.msg);
					return false;
				}
				return true;
			}
			return false;
		});
	commands ~= UserCommand("dt", "--display-track", "Display track {index} {variation}", "dt {intTrackIndex} {intTrackVariation}",
		(string[] args) {
			if (args.length == 3)
			{
				try
				{
					displayTrack(parse!int(args[1]), parse!int(args[2]));
				}
				catch (ConvException e)
				{
					writeln(e.msg);
					return false;
				}
				return true;
			}
			return false;
		});
	commands ~= UserCommand("e", "extract", "Extract and inflate zlib data {offset}");
	commands ~= UserCommand("ecb", "extract-car-binary", "Extract car {index} binary data");
	commands ~= UserCommand("eco", "extract-car-obj", "Extract car {index} converted to Wavefront Obj format", "", &extractCarObj);
	commands ~= UserCommand("ico", "import-car-obj", "Import car from Wavefront Obj file", "ico {path/to/obj}", &importCarObj);
	commands ~= UserCommand("etb", "extract-track", "Extract track {index} {variation} binary data");
	commands ~= UserCommand("h", "help", "Display all available commands", "", &writeHelp);
	commands ~= UserCommand("v", "version", "Version information", "", (string[] args) { writeln(RELEASE_VERSION); return true; });
}