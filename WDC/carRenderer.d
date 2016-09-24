module wdc.carRenderer;

import camera,
	   gfm.math,
	   gfm.opengl,
	   wdc.car,
	   wdc.tools,
	   wdc.renderer;
import std.stdio,
	   std.format,
	   std.file,
	   std.bitmanip;

class CarRenderer : Renderer
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

		int modelBlockIndex = -1;
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

		ubyte[] data;
	}

	this(Car source, OpenGL openglInstance)
	{
		openGL = openglInstance;
		program = createShader(openGL);
		model = mat4f.identity();

		vs = new VertexSpecification!Vertex(program);

		data = source.data;

		insertPalettes(source.palettes1);
		insertTextures(source.textures);

		while (data.readInt(modelBlockPointerOffset + (numModelBlocks * 0x10)) > 0)
		{
			numModelBlocks++;
		}

		setupBuffers();
	}

	void draw(Camera camera, char[] args)
	{
		parseInput(args);
		if (modelBlockIndex == -1)
		{
			program.uniform("textureSampler").set(0);
			program.uniform("mvpMatrix").set(camera.getPVM(model));
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
			program.uniform("mvpMatrix").set(camera.getPVM(model));
			program.use();
			partVAO.bind();
			vs.use();
			glDrawArrays(GL_TRIANGLES, 0, partVertices.length);
			partVAO.unbind();
			program.unuse();
		}
	}

	private void loadModelData()
	{
		loadVertices(partVertices, modelBlockIndex);
		loadTexture(partTextureBytes, modelBlockIndex);

		if (partVertices.length < 3)
		{
			writeln("NOTE: Too few vertices defined to draw anything");
		}
	}

	private void insertPalettes(ubyte[] palettes)
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
				data[destinationOffset + i] = replacementData[i];
				i++;
			}
		}

		int palettePointerOffset = 0x7c;
		enum endPalettePointers = 0x9c;

		int paletteOffset;
		int paletteNum = 0;

		while (palettePointerOffset < endPalettePointers)
		{
			paletteOffset = peek!int(data[palettePointerOffset..palettePointerOffset + 4]);
			assert(paletteOffset != 0, "This car has less than 8 inserted palettes?");

			insertPalette(paletteOffset, palettes[paletteNum * 0x20..(paletteNum * 0x20) + 0x20]);

			palettePointerOffset += 4;
			paletteNum++;
		}

		palettesOffset = peek!int(data[0..4]) + 4; // Correct ??
		while (data.readInt(palettesOffset + (paletteSize * numPalettes)) != 0)
		{
			numPalettes++;
		}
	}

	private void insertTextures(ubyte[] textures)
	{
		void insertTexture(int destinationOffset, int sourceOffset, int size)
		{
			int endOffset = sourceOffset + size;
			while (sourceOffset < endOffset)
			{
				data[destinationOffset] = textures[sourceOffset];
				sourceOffset++;
				destinationOffset++;
			}
		}
		
		int textureDescriptorTableOffset = peek!int(data[0xb4..0xb8]);
		int textureCount = peek!int(data[0xb8..0xbc]);
		int curTextureNum = 0;

		int textureDescriptorOffset;
		int textureSize;
		int textureDestination;
		int sourcePosition = 0;

		while (curTextureNum < textureCount)
		{
			textureDescriptorOffset = peek!int(data[textureDescriptorTableOffset + curTextureNum * 4
													..
													textureDescriptorTableOffset + 4 + curTextureNum * 4]);
			textureDestination = peek!int(data[textureDescriptorOffset + 4
												..
												textureDescriptorOffset + 8]);
			textureSize = peek!int(data[textureDescriptorOffset + 0x14
										..
										textureDescriptorOffset + 0x18]);
			textureSize = (((textureSize >> 0xc) & 0xfff) << 1) + 2;

			insertTexture(textureDestination, sourcePosition, textureSize);

			sourcePosition += textureSize;
			curTextureNum++;
		}
	}

	private void setupBuffers()
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

	private void parseInput(char[] keys)
	{
		foreach(key; keys)
		{
			if (key == '1')
			{
				setModelBlock(modelBlockIndex - 1);
			}
			else if (key == '2')
			{
				setModelBlock(modelBlockIndex + 1);
			}
			if (key == '3')
			{
				paletteIndex--;
				paletteIndex = paletteIndex < 0 ? numPalettes - 1 : paletteIndex;
				loadModelData();
				updateBuffers();
			}
			else if (key == '4')
			{
				paletteIndex++;
				paletteIndex = paletteIndex >= numPalettes ? 0 : paletteIndex;
				loadModelData();
				updateBuffers();
				writefln("Model:%.2X palette:%.2X", modelBlockIndex, paletteIndex);
			}
		}
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

	void updateBuffers()
	{
		partVBO.setData(partVertices[]);
		setupTextures(partTexture, partTextureBytes);
	}

	private void setupTextures(ref GLTexture2D curTexture, ref ubyte[] textureBytes)
	{
		//std.file.write(format("car tex #%.2X.raw", modelBlockIndex), textureBytes);
		curTexture = new GLTexture2D(openGL);
		curTexture.setMinFilter(GL_LINEAR);
		curTexture.setMagFilter(GL_LINEAR);
		if (modelBlockIndex < 0x1D)
		{
			curTexture.setWrapS(GL_CLAMP_TO_EDGE);
			curTexture.setWrapT(GL_CLAMP_TO_EDGE);
		}
		else
		{
			// wheels
			curTexture.setWrapS(GL_MIRRORED_REPEAT);
			curTexture.setWrapT(GL_MIRRORED_REPEAT);
		}
		curTexture.setImage(0, GL_RGBA, 80, 38, 0, GL_RGBA, GL_UNSIGNED_SHORT_5_5_5_1, textureBytes.ptr);
	}

	private void loadVertices(ref Vertex[] vertices, int modelIndex)
	{
		Vertex getVertex(int vertexOffset, int polygonOffset, int vertNum, int normalOffset)
		{
			return Vertex(vec3i(peek!short(data[vertexOffset + 2..vertexOffset + 4]),
			                    peek!short(data[vertexOffset + 4..vertexOffset + 6]),
			                    peek!short(data[vertexOffset    ..vertexOffset + 2])),
			              vec2f(cast(byte)data[polygonOffset + 0x10 + vertNum * 2] / cast(float)textureWidth,
			                    cast(byte)data[polygonOffset + 0x11 + vertNum * 2] / cast(float)textureHeight),
			              vec3i(cast(int)cast(byte)data[normalOffset + 1],
			                    cast(int)cast(byte)data[normalOffset + 2],
			                    cast(int)cast(byte)data[normalOffset]));
		}
		
		int pointerOffset = modelBlockPointerOffset + modelIndex * 0x10;
		int modelBlockOffset = peek!int(data[pointerOffset..pointerOffset + 4]);
		int verticesOffset = peek!int(data[modelBlockOffset + 0 .. modelBlockOffset + 4]);
		//int vertexCount = peek!int(data[modelBlockOffset + 4 .. modelBlockOffset + 8]);
		int polygonOffset = peek!int(data[modelBlockOffset + 8 .. modelBlockOffset + 12]);
		int polygonCount = peek!int(data[modelBlockOffset + 12 .. modelBlockOffset + 16]);
		int normalsOffset = peek!int(data[modelBlockOffset + 0x20 .. modelBlockOffset + 0x24]);
		//int normalsCount = peek!int(data[modelBlockOffset + 0x24 .. modelBlockOffset + 0x28]);

		if (modelBlockOffset == 0) {
			return;
		}
		
		vertices.length = 0;
		ushort v1, v2, v3, v4, n1, n2, n3, n4;
		int curVertOffset, curNormalOffset;

		while (polygonCount > 0)
		{
			v1 = peek!ushort(data[polygonOffset + 8 .. polygonOffset + 10]);
			v2 = peek!ushort(data[polygonOffset + 10 .. polygonOffset + 12]);
			v3 = peek!ushort(data[polygonOffset + 12 .. polygonOffset + 14]);
			v4 = peek!ushort(data[polygonOffset + 14 .. polygonOffset + 16]);

			n1 = peek!ushort(data[polygonOffset + 0x18 .. polygonOffset + 0x1a]);
			n2 = peek!ushort(data[polygonOffset + 0x1a .. polygonOffset + 0x1c]);
			n3 = peek!ushort(data[polygonOffset + 0x1c .. polygonOffset + 0x1e]);
			n4 = peek!ushort(data[polygonOffset + 0x1e .. polygonOffset + 0x20]);

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

	private void loadTexture(ref ubyte[] texBytes, int modelIndex)
	{
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

		texBytes.length = 0;
		int pointerOffset = modelBlockPointerOffset + modelIndex * 0x10;
		int modelBlockOffset = peek!int(data[pointerOffset..pointerOffset + 4]);
		int polygonOffset = peek!int(data[modelBlockOffset + 8 .. modelBlockOffset + 12]);
		int polygonCount = peek!int(data[modelBlockOffset + 12 .. modelBlockOffset + 16]);
		if (polygonCount <= 0 || modelBlockOffset == 0)
		{
			return;
		}
		int textureNum = data[polygonOffset + 4];
		int textureCmdPointers = peek!int(data[textureCMDPointersOffset..textureCMDPointersOffset + 4]);
		int textureCmdPointer = textureCmdPointers + modelIndex * 4;
		int textureCmdOffset = peek!int(data[textureCmdPointer..textureCmdPointer + 4]);

		int textureOffset = peek!int(data[textureCmdOffset + 4..textureCmdOffset + 8]);

		int maxWidth = textureWidth / 2;
		int maxHeight = textureHeight;
		
		ubyte[] textureIndices;
		textureIndices.length = maxWidth * maxHeight;
		textureIndices[] = data[textureOffset..textureOffset + textureIndices.length];
		straightenIndices(textureIndices, maxWidth, maxHeight);
		// TODO: how the func does it decide which palette to use?

		int w = 0, h = 0;
		ubyte index;
		auto palette = data[palettesOffset + (paletteIndex * paletteSize)
								..
								palettesOffset + (paletteIndex * paletteSize) + paletteSize];
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

	private auto createShader(OpenGL opengl)
	{
		string tunnelProgramSource =
			q{#version 330 core

			#if VERTEX_SHADER
			in ivec3 position;
			in vec2 vertexUV;

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
			out vec4 color;
			uniform sampler2D textureSampler;

			void main()
			{
				color = texture( textureSampler, UV ).rgba;
			}
			#endif
		};

		return new GLProgram(opengl, tunnelProgramSource);
	}
}