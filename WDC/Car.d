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
		Vertex[] partVertices;
		mat4f model;
		GLProgram program;
		OpenGL openGL;
		GLVAO partVAO;
		GLBuffer partVBO;
		VertexSpecification!Vertex vs;
		VertexSpecification!Vertex vs2;

		ubyte[] dataBlob;

		int modelBlockIndex;
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
		GLTexture2D partTexture;
		ubyte[] partTextureBytes;

		enum numCarParts = 26;
		ubyte[][numCarParts] carTextureBytes;
		GLTexture2D[numCarParts] carTextures;
		GLVAO[numCarParts] carVAOs;
		GLBuffer[numCarParts] carVBOs;
		Vertex[][numCarParts] carVertices;
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
		setModelBlock(-1);
	}

	void draw(Camera cam)
	{
		if (modelBlockIndex == -1)
		{
			program.uniform("textureSampler").set(0);
			program.uniform("mvpMatrix").set(cam.getPVM(model));
			for (int i = 0; i < numCarParts; i++)
			{
				carTextures[i].use(0);
				program.use();
				carVAOs[i].bind();
				carVBOs[i].bind();
				vs.use();
				glDrawArrays(GL_TRIANGLES, 0, carVertices[i].length);
				carVAOs[i].unbind();
				program.unuse();
			}
		}
		else
		{
			partTexture.use(0);
			program.uniform("textureSampler").set(0);
			program.uniform("mvpMatrix").set(cam.getPVM(model));
			program.use();
			partVAO.bind();
			vs.use();
			glDrawArrays(GL_TRIANGLES, 0, partVertices.length);
			partVAO.unbind();
			program.unuse();
		}
	}

	void drawNormals(Camera cam, GLProgram prgm)
	{
		prgm.uniform("mvpMatrix").set(cam.getPVM(model));
		prgm.use();
		partVAO.bind();
		vs2.use();
		glDrawArrays(GL_TRIANGLES, 0, partVertices.length);
		partVAO.unbind();
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

	void setModelBlock(int newblockNum)
	{
		if (newblockNum < -1)
		{
			modelBlockIndex = numModelBlocks - 1;
		}
		else if (newblockNum >= numModelBlocks)
		{
			modelBlockIndex = -1;
		}
		else
		{
			modelBlockIndex = newblockNum;
		}

		if (modelBlockIndex != -1)
		{
			loadModelData();
			updateBuffers();
		}
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
		writefln("p%x", paletteIndex);
		loadTexture(partTextureBytes, modelBlockIndex);
		setupTextures(partTexture, partTextureBytes);
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
			replacementData[0..2] = [0,0];
			// rather than guessing like that
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

			insertPalette(paletteOffset, palettes[paletteNum * 0x20..(paletteNum * 0x20) + 0x20]);

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
	}

	void updateBuffers()
	{
		partVBO.setData(partVertices[]);
		setupTextures(partTexture, partTextureBytes);
	}

	void setupBuffers()
	{
		partVAO = new GLVAO(openGL);
		partVAO.bind();
		partVBO = new GLBuffer(openGL, GL_ARRAY_BUFFER, GL_STATIC_DRAW, partVertices[]);
		partVAO.unbind();
		setupTextures(partTexture, partTextureBytes);

		for (int i = 0; i < numCarParts; i++)
		{
			// load car verts
			loadVertices(carVertices[i], i);
			// load car textures
			loadTexture(carTextureBytes[i], i);
			carVAOs[i] = new GLVAO(openGL);
			carVAOs[i].bind();
			carVBOs[i] = new GLBuffer(openGL, GL_ARRAY_BUFFER, GL_STATIC_DRAW, carVertices[i][]);
			carVAOs[i].unbind();
			setupTextures(carTextures[i], carTextureBytes[i]);
		}
	}

	void loadModelData()
	{
		loadVertices(partVertices, modelBlockIndex);
		loadTexture(partTextureBytes, modelBlockIndex);

		if (partVertices.length < 3)
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

	void loadTexture(ref ubyte[] texBytes, int modelIndex)
	{
		texBytes.length = 0;
		int pointerOffset = modelBlockPointerOffset + modelIndex * 0x10;
		int modelBlockOffset = peek!int(dataBlob[pointerOffset..pointerOffset + 4]);
		int polygonOffset = peek!int(dataBlob[modelBlockOffset + 8 .. modelBlockOffset + 12]);
		int polygonCount = peek!int(dataBlob[modelBlockOffset + 12 .. modelBlockOffset + 16]);
		if (polygonCount <= 0)
		{
			return;
		}
		int textureNum = dataBlob[polygonOffset + 4];
		writeln(textureNum);
		// use modelBlockIndex to index into the first lot of texture descriptor pointers
		int textureCmdPointers = peek!int(dataBlob[textureCMDPointersOffset..textureCMDPointersOffset + 4]);
		int textureCmdPointer = textureCmdPointers + textureNum * 4;
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
		auto palette = dataBlob[palettesOffset + paletteIndex * paletteSize
								..
								palettesOffset + paletteIndex * paletteSize + paletteSize];
		while (h < maxHeight)
		{
			w = 0;
			while (w < maxWidth)
			{
				index = ((textureIndices[ w + (h * maxWidth)] & 0xf0) >> 3) ;
				texBytes ~= palette[index + 1];
				texBytes ~= palette[index];
				
				index = (textureIndices[w + (h * maxWidth)] & 0x0f) * 2;
				texBytes ~= palette[index + 1];
				texBytes ~= palette[index];
				w++;
			}
			h++;
		}
	}

	void setupTextures(ref GLTexture2D curTexture, ref ubyte[] textureBytes)
	{
		//if (curTexture)
		//{
		//	delete curTexture;
		//}
		curTexture = new GLTexture2D(openGL);
		curTexture.setMinFilter(GL_LINEAR);
		curTexture.setMagFilter(GL_LINEAR);
		// 3D wheel models want to use GL_MIRRORED_REPEAT
		curTexture.setWrapS(GL_CLAMP_TO_EDGE);
		curTexture.setWrapT(GL_CLAMP_TO_EDGE);
		curTexture.setImage(0, GL_RGBA, 80, 38, 0, GL_RGBA, GL_UNSIGNED_SHORT_5_5_5_1, textureBytes.ptr);
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

	void loadVertices(ref Vertex[] vertices, int modelIndex)
	{
		int pointerOffset = modelBlockPointerOffset + modelIndex * 0x10;
		int modelBlockOffset = peek!int(dataBlob[pointerOffset..pointerOffset + 4]);
		int verticesOffset = peek!int(dataBlob[modelBlockOffset + 0 .. modelBlockOffset + 4]);
		//int vertexCount = peek!int(dataBlob[modelBlockOffset + 4 .. modelBlockOffset + 8]);
		int polygonOffset = peek!int(dataBlob[modelBlockOffset + 8 .. modelBlockOffset + 12]);
		int polygonCount = peek!int(dataBlob[modelBlockOffset + 12 .. modelBlockOffset + 16]);
		int normalsOffset = peek!int(dataBlob[modelBlockOffset + 0x20 .. modelBlockOffset + 0x24]);
		//int normalsCount = peek!int(dataBlob[modelBlockOffset + 0x24 .. modelBlockOffset + 0x28]);
		
		vertices.length = 0;
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
				vertices ~= getVertex(curVertOffset, polygonOffset, 0, curNormalOffset);
				curVertOffset = verticesOffset + v2 * 6;
				curNormalOffset = normalsOffset + n2 * 3;
				vertices ~= getVertex(curVertOffset, polygonOffset, 1, curNormalOffset);
				curVertOffset = verticesOffset + v3 * 6;
				curNormalOffset = normalsOffset + n3 * 3;
				vertices ~= getVertex(curVertOffset, polygonOffset, 2, curNormalOffset);
			}
			else // Two Triangles
			{
				curVertOffset = verticesOffset + v1 * 6;
				curNormalOffset = normalsOffset + n1 * 3;
				vertices ~= getVertex(curVertOffset, polygonOffset, 0, curNormalOffset);
				curVertOffset = verticesOffset + v2 * 6;
				curNormalOffset = normalsOffset + n2 * 3;
				vertices ~= getVertex(curVertOffset, polygonOffset, 1, curNormalOffset);
				curVertOffset = verticesOffset + v3 * 6;
				curNormalOffset = normalsOffset + n3 * 3;
				vertices ~= getVertex(curVertOffset, polygonOffset, 2, curNormalOffset);

				curVertOffset = verticesOffset + v1 * 6;
				curNormalOffset = normalsOffset + n1 * 3;
				vertices ~= getVertex(curVertOffset, polygonOffset, 0, curNormalOffset);
				curVertOffset = verticesOffset + v3 * 6;
				curNormalOffset = normalsOffset + n3 * 3;
				vertices ~= getVertex(curVertOffset, polygonOffset, 2, curNormalOffset);
				curVertOffset = verticesOffset + v4 * 6;
				curNormalOffset = normalsOffset + n4 * 3;
				vertices ~= getVertex(curVertOffset, polygonOffset, 3, curNormalOffset);
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