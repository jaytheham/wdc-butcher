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

	void nextModelBlock()
	{
		//setModelBlock(modelBlockIndex + 1);
	}

	void prevModelBlock()
	{
		//setModelBlock(modelBlockIndex - 1);
	}

	void setModelBlock(int newblockNum)
	{
		if (newblockNum < -1)
		{
			//modelBlockIndex = numModelBlocks - 1;
		}
		//else if (newblockNum >= numModelBlocks)
		//{
		//	modelBlockIndex = -1;
		//}
		else
		{
		//	modelBlockIndex = newblockNum;
		}

		//if (modelBlockIndex != -1)
		//{
		//	loadModelData();
		//	updateBuffers();
		//}
	}

	void nextPalette()
	{
		//setPalette(paletteIndex + 1);
	}

	void prevPalette()
	{
		//setPalette(paletteIndex - 1);
	}

	void setPalette(int paletteNum)
	{
		//paletteIndex = paletteNum;
		//if (paletteIndex < 0)
		//{
	//		paletteIndex = numPalettes - 1;
		//}
		//else if (paletteIndex >= numPalettes)
		//{
		//	paletteIndex = 0;
		//}
	//	writefln("p%x", paletteIndex);
		//loadTexture(partTextureBytes, modelBlockIndex);
		//setupTextures(partTexture, partTextureBytes);
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

	void createFromModel(ubyte[] data)
	{
		writeln("**** UNIMPLEMENTED ****");
	}

	void updateBuffers()
	{
		//partVBO.setData(partVertices[]);
		//setupTextures(partTexture, partTextureBytes);
	}

	void loadModelData()
	{
		//loadVertices(partVertices, modelBlockIndex);
		//loadTexture(partTextureBytes, modelBlockIndex);

		//if (partVertices.length < 3)
		//{
		//	writeln("NOTE: Too few vertices defined to draw anything");
		//}
	}
}