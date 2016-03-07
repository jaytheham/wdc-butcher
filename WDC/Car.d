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
			vec3i inNormal;
		}
		Vertex[] carVertices;
		mat4f model;
		GLProgram program;
		OpenGL openGL;
		GLVAO vao;
		GLBuffer vbo;
		VertexSpecification!Vertex vs;
		VertexSpecification!Vertex vs2;

		ubyte[] dataBlob;

		int modelBlockIndex = 0;
		int numModelBlocks = 0;

		int paletteIndex = 0;
		int numPalettes = 0;
		int palettesOffset;
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

	void enableDrawing(OpenGL opengl, GLProgram prgrm, GLProgram prgrm2)
	{
		openGL = opengl;
		program = prgrm;
		model = mat4f.identity();

		vs = new VertexSpecification!Vertex(program);
		vs2 = new VertexSpecification!Vertex(prgrm2);

		setupBuffers();
	}

	void draw(Camera cam)
	{
		texture.use(0);
		program.uniform("textureSampler").set(0);
		program.uniform("mvpMatrix").set(cam.getPVM(model));
		program.use();
		vao.bind();
		vs.use();
		glDrawArrays(GL_TRIANGLES, 0, carVertices.length);
		vao.unbind();
		program.unuse();
	}

	void drawNormals(Camera cam, GLProgram prgm)
	{
		
		prgm.uniform("normalsLength").set(1.0F);
		prgm.uniform("mvpMatrix").set(cam.getPVM(model));
		prgm.use();
		vao.bind();
		vs2.use();
		glDrawArrays(GL_TRIANGLES, 0, carVertices.length);
		vao.unbind();
		prgm.unuse();
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
	void insertTextures(ubyte[] textures)
	{
		void insertTexture(int destinationOffset, int sourceOffset, int size)
		{
			int endOffset = sourceOffset + size;
			while (sourceOffset < endOffset)
			{
				dataBlob[destinationOffset] = textures[sourceOffset];
				sourceOffset++;
				destinationOffset++;
			}
		}
		
		int textureDescriptorTableOffset = peek!int(dataBlob[0xb4..0xb8]); // Is this always here ?
		int textureCount = peek!int(dataBlob[0xb8..0xbc]);
		int curTextureNum = 0;

		int textureDescriptorOffset;
		int textureSize;
		int textureDestination;
		int sourcePosition = 0;

		while (curTextureNum < textureCount)
		{
			textureDescriptorOffset = peek!int(dataBlob[textureDescriptorTableOffset + curTextureNum * 4
													..
													textureDescriptorTableOffset + 4 + curTextureNum * 4]);
			textureDestination = peek!int(dataBlob[textureDescriptorOffset + 4
												..
												textureDescriptorOffset + 8]);
			textureSize = peek!int(dataBlob[textureDescriptorOffset + 0x14
										..
										textureDescriptorOffset + 0x18]);
			textureSize = (((textureSize >> 0xc) & 0xfff) << 1) + 2;

			insertTexture(textureDestination, sourcePosition, textureSize);

			sourcePosition += textureSize;
			curTextureNum++;
		}
	}

	void insertPalettes(ubyte[] palettes)
	{
		void insertPalette(int destinationOffset, ubyte[] replacementData)
		{
			// TODO, this should do whatever it is the game does that replaces the invisible color
			int endOffset = destinationOffset + replacementData.length;
			int i = 0;
			while (destinationOffset + i < endOffset)
			{
				dataBlob[destinationOffset + i] = replacementData[i];
				i++;
			}
		}

		int palettePointerOffset = 0x7c;
		enum endPalettePointers = 0x9c;

		int paletteOffset;
		int paletteNum = 0;

		while (palettePointerOffset < endPalettePointers)
		{
			paletteOffset = peek!int(dataBlob[palettePointerOffset..palettePointerOffset + 4]);
			assert(paletteOffset != 0, "This car has less than 8 inserted palettes?");

			insertPalette(paletteOffset, palettes[paletteNum * 4..paletteNum * 4 + 0x20]);

			palettePointerOffset += 4;
			paletteNum++;
		}

		palettesOffset = peek!int(dataBlob[0..4]) + 4; // Correct ??
		while (peek!int(dataBlob[palettesOffset + (paletteSize * numPalettes)
								..
								palettesOffset + (paletteSize * numPalettes) + 4]) != 0)
		{
			numPalettes++;
		}
	}

	void createFromBinary(ubyte[] data, ubyte[] textures, ubyte[] palettes)
	{
		dataBlob = data;
		insertPalettes(palettes);
		insertTextures(textures);

		while (peek!int(dataBlob[modelBlockPointerOffset + (numModelBlocks * 0x10)
		                         ..
		                         modelBlockPointerOffset + (numModelBlocks * 0x10) + 4]) > 0)
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
		// use modelBlockIndex to index into the first lot of texture descriptor pointers
		int textureCmdPointers = peek!int(dataBlob[textureCMDPointersOffset..textureCMDPointersOffset + 4]);
		int textureCmdPointer = textureCmdPointers + modelBlockIndex * 4;
		int textureCmdOffset = peek!int(dataBlob[textureCmdPointer..textureCmdPointer + 4]);

		int textureOffset = peek!int(dataBlob[textureCmdOffset + 4..textureCmdOffset + 8]);

		int maxWidth = textureWidth / 2;
		int maxHeight = textureHeight;
		
		ubyte[] textureIndices;
		textureIndices.length = maxWidth * maxHeight;
		textureIndices[] = dataBlob[textureOffset..textureOffset + textureIndices.length];
		straightenIndices(textureIndices, maxWidth, maxHeight);
		// TODO: how the func does it decide which palette to use?

		int w = 0, h = 0;
		ubyte index;
		auto palette = dataBlob[palettesOffset + paletteIndex * paletteSize..palettesOffset + paletteIndex * paletteSize + paletteSize];
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
		if (texture)
		{
			delete texture;
		}
		texture = new GLTexture2D(openGL);
		texture.setMinFilter(GL_LINEAR);
		texture.setMagFilter(GL_LINEAR);
		texture.setImage(0, GL_RGBA, 80, 38, 0, GL_RGBA, GL_UNSIGNED_SHORT_5_5_5_1, textureBytes.ptr);
	}

	Vertex getVertex(int vertexOffset, int polygonOffset, int vertNum, int normalOffset)
	{
		return Vertex(vec3i(peek!short(dataBlob[vertexOffset    ..vertexOffset + 2]),
							peek!short(dataBlob[vertexOffset + 4..vertexOffset + 6]),
						   -peek!short(dataBlob[vertexOffset + 2..vertexOffset + 4])),
					  vec2f(cast(byte)dataBlob[polygonOffset + 0x10 + vertNum * 2] / cast(float)textureWidth,
							cast(byte)dataBlob[polygonOffset + 0x11 + vertNum * 2] / cast(float)textureHeight),
					  vec3i(cast(int)cast(byte)dataBlob[normalOffset],
					  		cast(int)cast(byte)dataBlob[normalOffset + 2],
					  	   -cast(int)cast(byte)dataBlob[normalOffset + 1]));
	}

	void loadVertices()
	{
		int pointerOffset = modelBlockPointerOffset + modelBlockIndex * 0x10;
		int modelBlockOffset = peek!int(dataBlob[pointerOffset..pointerOffset + 4]);
		int verticesOffset = peek!int(dataBlob[modelBlockOffset + 0 .. modelBlockOffset + 4]);
		//int vertexCount = peek!int(dataBlob[modelBlockOffset + 4 .. modelBlockOffset + 8]);
		int polygonOffset = peek!int(dataBlob[modelBlockOffset + 8 .. modelBlockOffset + 12]);
		int polygonCount = peek!int(dataBlob[modelBlockOffset + 12 .. modelBlockOffset + 16]);
		int normalsOffset = peek!int(dataBlob[modelBlockOffset + 0x20 .. modelBlockOffset + 0x24]);
		//int normalsCount = peek!int(dataBlob[modelBlockOffset + 0x24 .. modelBlockOffset + 0x28]);
		
		carVertices.length = 0;
		ushort v1, v2, v3, v4, n1, n2, n3, n4;
		int curVertOffset, curNormalOffset;

		while (polygonCount > 0)
		{
			v1 = peek!ushort(dataBlob[polygonOffset + 8 .. polygonOffset + 10]);
			v2 = peek!ushort(dataBlob[polygonOffset + 10 .. polygonOffset + 12]);
			v3 = peek!ushort(dataBlob[polygonOffset + 12 .. polygonOffset + 14]);
			v4 = peek!ushort(dataBlob[polygonOffset + 14 .. polygonOffset + 16]);

			n1 = peek!ushort(dataBlob[polygonOffset + 0x18 .. polygonOffset + 0x1a]);
			n2 = peek!ushort(dataBlob[polygonOffset + 0x1a .. polygonOffset + 0x1c]);
			n3 = peek!ushort(dataBlob[polygonOffset + 0x1c .. polygonOffset + 0x1e]);
			n4 = peek!ushort(dataBlob[polygonOffset + 0x1e .. polygonOffset + 0x20]);

			if (v4 == 0xffff) // One triangle
			{
				curVertOffset = verticesOffset + v1 * 6;
				curNormalOffset = normalsOffset + n1 * 3;
				carVertices ~= getVertex(curVertOffset, polygonOffset, 0, curNormalOffset);
				curVertOffset = verticesOffset + v2 * 6;
				curNormalOffset = normalsOffset + n2 * 3;
				carVertices ~= getVertex(curVertOffset, polygonOffset, 1, curNormalOffset);
				curVertOffset = verticesOffset + v3 * 6;
				curNormalOffset = normalsOffset + n3 * 3;
				carVertices ~= getVertex(curVertOffset, polygonOffset, 2, curNormalOffset);
			}
			else // Two Triangles
			{
				curVertOffset = verticesOffset + v1 * 6;
				curNormalOffset = normalsOffset + n1 * 3;
				carVertices ~= getVertex(curVertOffset, polygonOffset, 0, curNormalOffset);
				curVertOffset = verticesOffset + v2 * 6;
				curNormalOffset = normalsOffset + n2 * 3;
				carVertices ~= getVertex(curVertOffset, polygonOffset, 1, curNormalOffset);
				curVertOffset = verticesOffset + v3 * 6;
				curNormalOffset = normalsOffset + n3 * 3;
				carVertices ~= getVertex(curVertOffset, polygonOffset, 2, curNormalOffset);

				curVertOffset = verticesOffset + v1 * 6;
				curNormalOffset = normalsOffset + n1 * 3;
				carVertices ~= getVertex(curVertOffset, polygonOffset, 0, curNormalOffset);
				curVertOffset = verticesOffset + v3 * 6;
				curNormalOffset = normalsOffset + n3 * 3;
				carVertices ~= getVertex(curVertOffset, polygonOffset, 2, curNormalOffset);
				curVertOffset = verticesOffset + v4 * 6;
				curNormalOffset = normalsOffset + n4 * 3;
				carVertices ~= getVertex(curVertOffset, polygonOffset, 3, curNormalOffset);
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