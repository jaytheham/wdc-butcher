module wdc.car;

import std.stdio,
	   std.array,
	   std.file,
	   std.bitmanip,
	   std.typecons,
	   camera,
	   gfm.math,
	   gfm.opengl,
	   wdc.drawable,
	   wdc.renderer,
	   wdc.carRenderer;
// Car should accept either:
//  Binary files from the ROM
//  3D model files
// and convert them into an understandable, intermediate format from which it can output ROM compatible binaries
class Car : Drawable
{
	ubyte[] dataBlob;
	ubyte[] textures;
	ubyte[] palettes1;
	ubyte[] palettes2;
	ubyte[] palettes3;

	private
	{
		CarRenderer renderer;
	}

	this(ubyte[] data, ubyte[] textures, ubyte[] palettesA, ubyte[] palettesB, ubyte[] palettesC)
	{
		createFromBinary(data, textures, palettesA, palettesB, palettesC);
	}

	void setupDrawing(OpenGL opengl)
	{
		renderer = new CarRenderer(this, opengl);
	}

	void draw(Camera camera)
	{
		renderer.draw(camera);
	}


private:
	void createFromBinary(ubyte[] data, ubyte[] textureSource, ubyte[] palettesA, ubyte[] palettesB, ubyte[] palettesC)
	{
		dataBlob = data;
		textures = textureSource;
		palettes1 = palettesA;
		palettes2 = palettesB;
		palettes3 = palettesC;
	}
}