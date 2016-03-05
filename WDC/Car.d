module wdc.car;

import std.stdio,
	   std.array,
	   std.file,
	   std.bitmanip,
	   std.typecons;

import camera;

import gfm.math,
	   gfm.opengl;

class Car
{
	private
	{
		struct Vertex
		{
			vec3i position;
			vec2f vertexUV;
		}

		ubyte[] dataBlob;
		ubyte[0x100] palettes;
		Vertex[] carVertices;
		mat4f model;
		GLProgram program;
		OpenGL openGL;
		GLVAO vao;
		GLBuffer vbo;
		VertexSpecification!Vertex vs;

		int modelBlockIndex = 0;
		int numModelBlocks = 0;

		int paletteIndex = 0;
		immutable int numPalettes = 8;
		immutable int paletteSize = 0x20;

		enum modelBlockPointerOffset = 0xf4;
		enum textureCMDPointersOffset = 0xa0;
		enum textureBlobOffset = 0x538;

		int textureWidth = 80;
		int textureHeight = 38;
		GLTexture2D texture;
		ubyte[] textureBytes;
	}

	this(ubyte[] data, ubyte[] textures, ubyte[] carPalettes)
	{
		createFromBinary(data, textures, carPalettes);
	}

	void enableDrawing(OpenGL opengl, GLProgram prgrm)
	{
		openGL = opengl;
		program = prgrm;
		model = mat4f.identity();

		vs = new VertexSpecification!Vertex(program);

		setupBuffers();
	}

	void draw(Camera cam)
	{
		texture.use(0);
		program.uniform("myTextureSampler").set(0);
		program.uniform("mvpMatrix").set(cam.getPVM(model));
		program.use();
		vao.bind();
		glDrawArrays(GL_TRIANGLES, 0, carVertices.length);
		vao.unbind();
		program.unuse();
	}

	void nextModelBlock()
	{
		setModelBlock(modelBlockIndex + 1);
	}

	void prevModelBlock()
	{
		setModelBlock(modelBlockIndex - 1);
	}

	void setModelBlock(int blockNum)
	{
		modelBlockIndex = blockNum;
		if (modelBlockIndex < 0)
		{
			modelBlockIndex = numModelBlocks - 1;
		}
		else if (modelBlockIndex >= numModelBlocks)
		{
			modelBlockIndex = 0;
		}
		loadModelData();
		updateBuffers();
	}

	void nextPalette()
	{
		setPalette(paletteIndex + 1);
	}

	void prevPalette()
	{
		setPalette(paletteIndex - 1);
	}

	void setPalette(int paletteNum)
	{
		paletteIndex = paletteNum;
		if (paletteIndex < 0)
		{
			paletteIndex = numPalettes - 1;
		}
		else if (paletteIndex >= numPalettes)
		{
			paletteIndex = 0;
		}
		loadTexture();
		setupTextures();
	}

private:
	// Is this the "correct" way of setting the texture start? Does it fail for any cars?
	int getTextureStart(ubyte[] data)
	{
		int lastInsertedPalette = peek!int(data[0x7c..0x80]);
		int num = 1;
		int nextPalette;
		while (num < 8)
		{
			nextPalette = peek!int(data[0x7c + num * 4..0x80 + num * 4]);
			lastInsertedPalette = lastInsertedPalette > nextPalette ? lastInsertedPalette : nextPalette;
			num++;
		}
		lastInsertedPalette += 0x20;
		int testValue = peek!int(data[lastInsertedPalette..lastInsertedPalette + 4]);
		while (testValue != 0)
		{
			lastInsertedPalette += 0x20;
			testValue = peek!int(data[lastInsertedPalette..lastInsertedPalette + 4]);
		}
		writefln("Texture start: %x", lastInsertedPalette);
		return lastInsertedPalette;
	}

	void createFromBinary(ubyte[] data, ubyte[] textures, ubyte[] carPalettes)
	{
		int textureStart = getTextureStart(data);
		// Here we clip the texture data because uncompress seems to be giving enlarged output sometimes
		dataBlob = replaceSlice(data, data[textureStart..textureStart + 0x8e80], textures[0..0x8e80]);
		
		//std.file.write("datablob", dataBlob);
		palettes[] = carPalettes[];

		while (peek!int(dataBlob[modelBlockPointerOffset + numModelBlocks * 0x10
		                         ..
		                         modelBlockPointerOffset + 4 + numModelBlocks * 0x10]) > 0)
		{
			numModelBlocks++;
		}
		
		loadModelData();
	}

	void updateBuffers()
	{
		vbo.setData(carVertices[]);
		setupTextures();
	}

	void setupBuffers()
	{
		vao = new GLVAO(openGL);
		vao.bind();
		vbo = new GLBuffer(openGL, GL_ARRAY_BUFFER, GL_STATIC_DRAW, carVertices[]);
		vs.use();
		vao.unbind();
		setupTextures();
	}

	void loadModelData()
	{
		loadVertices();
		loadTexture();

		if (carVertices.length < 3)
		{
			writeln("NOTE: Too few vertices defined to draw anything");
		}
	}

	void straightenIndices(ubyte[] rawIndices, int bytesWide, int height)
	{
		// Word swap the odd rows
		int w = 0, h = 0;
		ubyte[4] tempBytes;
		int byteNum;
		int curOffset;
		
		assert(bytesWide % 8 == 0, "ONLY WORKS FOR TEXTURES THAT ARE A MULTIPLE OF 16 WIDE!");

		while (h < height)
		{
			if (h % 2 == 1)
			{
				byteNum = 0;
				curOffset = h * bytesWide;
				while (byteNum < bytesWide)
				{
					tempBytes[] = rawIndices[curOffset + byteNum..curOffset + byteNum + 4];
					rawIndices[curOffset + byteNum..curOffset + byteNum + 4] = 
						rawIndices[curOffset + byteNum + 4..curOffset + byteNum + 8];
					rawIndices[curOffset + byteNum + 4..curOffset + byteNum + 8] = tempBytes[];

					byteNum += 8;
				}
			}
			h++;
		}
	}

	void loadTexture()
	{
		textureBytes.length = 0;
		// use modelBlockIndex to index into the first lot of texture pointer pointers
		int textureCmdPointers = peek!int(dataBlob[textureCMDPointersOffset..textureCMDPointersOffset + 4]);
		writefln("\n#%x @%x", modelBlockIndex, textureCmdPointers);
		int textureCmdPointer = textureCmdPointers + modelBlockIndex * 4;
		writefln("b %x", textureCmdPointer);
		int textureCmdOffset = peek!int(dataBlob[textureCmdPointer..textureCmdPointer + 4]);
		writefln("c %x", textureCmdOffset);

		int textureOffset = peek!int(dataBlob[textureCmdOffset + 4..textureCmdOffset + 8]);
		writefln("d %x", textureOffset);

		int maxWidth = textureWidth / 2;
		int maxHeight = textureHeight;
		
		ubyte[] textureIndices;
		textureIndices.length = maxWidth * maxHeight;
		textureIndices[] = dataBlob[textureOffset..textureOffset + textureIndices.length];
		straightenIndices(textureIndices, maxWidth, maxHeight);
		// TODO: how the func does it decide which palette to use?

		int w = 0, h = 0;
		ubyte index;
		auto palette = palettes[paletteIndex * paletteSize..paletteIndex * paletteSize + paletteSize];
		while (h < maxHeight)
		{
			w = 0;
			while (w < maxWidth)
			{
				index = ((textureIndices[ w + (h * maxWidth)] & 0xf0) >> 3) ;
				textureBytes ~= palette[index + 1];
				textureBytes ~= palette[index];
				
				index = (textureIndices[w + (h * maxWidth)] & 0x0f) * 2;
				textureBytes ~= palette[index + 1];
				textureBytes ~= palette[index];
				w++;
			}
			h++;
		}
	}

	void setupTextures()
	{
		texture = new GLTexture2D(openGL);
		texture.setMinFilter(GL_LINEAR);
		texture.setMagFilter(GL_LINEAR);
		texture.setImage(0, GL_RGBA, 80, 38, 0, GL_RGBA, GL_UNSIGNED_SHORT_5_5_5_1, textureBytes.ptr);
	}

	Vertex getVertex(int vertexOffset, int polygonOffset, int vertNum)
	{
		return Vertex(vec3i(peek!short(dataBlob[vertexOffset    ..vertexOffset + 2]),
							peek!short(dataBlob[vertexOffset + 4..vertexOffset + 6]),
							-peek!short(dataBlob[vertexOffset + 2..vertexOffset + 4])),
						vec2f(cast(byte)dataBlob[polygonOffset + 0x10 + vertNum * 2] / cast(float)textureWidth,
							  cast(byte)dataBlob[polygonOffset + 0x11 + vertNum * 2] / cast(float)textureHeight));
	}

	void loadVertices()
	{
		int pointerOffset = modelBlockPointerOffset + modelBlockIndex * 0x10;
		int modelBlockOffset = peek!int(dataBlob[pointerOffset..pointerOffset + 4]);
		int verticesOffset = peek!int(dataBlob[modelBlockOffset + 0 .. modelBlockOffset + 4]);
		//int vertexCount = peek!int(dataBlob[modelBlockOffset + 4 .. modelBlockOffset + 8]);
		int polygonOffset = peek!int(dataBlob[modelBlockOffset + 8 .. modelBlockOffset + 12]);
		int polygonCount = peek!int(dataBlob[modelBlockOffset + 12 .. modelBlockOffset + 16]);
		
		carVertices.length = 0;
		ushort v1, v2, v3, v4;
		int curVertOffset;

		while (polygonCount > 0)
		{
			v1 = peek!ushort(dataBlob[polygonOffset + 8 .. polygonOffset + 10]);
			v2 = peek!ushort(dataBlob[polygonOffset + 10 .. polygonOffset + 12]);
			v3 = peek!ushort(dataBlob[polygonOffset + 12 .. polygonOffset + 14]);
			v4 = peek!ushort(dataBlob[polygonOffset + 14 .. polygonOffset + 16]);

			if (v4 == 0xffff) // One triangle
			{
				curVertOffset = verticesOffset + v1 * 6;
				carVertices ~= getVertex(curVertOffset, polygonOffset, 0);
				curVertOffset = verticesOffset + v2 * 6;
				carVertices ~= getVertex(curVertOffset, polygonOffset, 1);
				curVertOffset = verticesOffset + v3 * 6;
				carVertices ~= getVertex(curVertOffset, polygonOffset, 2);
			}
			else // Two Triangles
			{
				curVertOffset = verticesOffset + v1 * 6;
				carVertices ~= getVertex(curVertOffset, polygonOffset, 0);
				curVertOffset = verticesOffset + v2 * 6;
				carVertices ~= getVertex(curVertOffset, polygonOffset, 1);
				curVertOffset = verticesOffset + v3 * 6;
				carVertices ~= getVertex(curVertOffset, polygonOffset, 2);

				curVertOffset = verticesOffset + v1 * 6;
				carVertices ~= getVertex(curVertOffset, polygonOffset, 0);
				curVertOffset = verticesOffset + v3 * 6;
				carVertices ~= getVertex(curVertOffset, polygonOffset, 2);
				curVertOffset = verticesOffset + v4 * 6;
				carVertices ~= getVertex(curVertOffset, polygonOffset, 3);
			}

			polygonOffset += 0x20;
			polygonCount--;
		}
	}

	void createFromModel(ubyte[] data)
	{
		writeln("**** UNIMPLEMENTED ****");
	}
}