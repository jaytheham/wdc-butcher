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

		Car src;
	}

	this(Car source, OpenGL openglInstance)
	{
		openGL = openglInstance;
		program = createShader(openGL);
		model = mat4f.identity();
		src = source;

		vs = new VertexSpecification!Vertex(program);

		data = source.modelsBinary;

		insertPalettes(source.palettes1Binary);
		insertTextures(source.texturesBinary);

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
			paletteOffset = data.readInt(palettePointerOffset);
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
			textureDescriptorOffset = data.readInt(textureDescriptorTableOffset + curTextureNum * 4);
			textureDestination = data.readInt(textureDescriptorOffset + 4);
			textureSize = data.readInt(textureDescriptorOffset + 0x14);
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
		else // wheels
		{
			curTexture.setWrapS(GL_MIRRORED_REPEAT);
			curTexture.setWrapT(GL_MIRRORED_REPEAT);
		}
		curTexture.setImage(0, GL_RGBA, 80, 38, 0, GL_RGBA, GL_UNSIGNED_SHORT_5_5_5_1, textureBytes.ptr);
	}

	private void loadVertices(ref Vertex[] vertices, int modelIndex)
	{
		Vertex getVertex(int vertexOffset, int polygonOffset, int vertNum, int normalOffset)
		{
			return Vertex(vec3i(data.readShort(vertexOffset + 2),
			                    data.readShort(vertexOffset + 4),
			                    data.readShort(vertexOffset)),
			              vec2f(cast(byte)data[polygonOffset + 0x10 + vertNum * 2] / cast(float)textureWidth,
			                    cast(byte)data[polygonOffset + 0x11 + vertNum * 2] / cast(float)textureHeight),
			              vec3i(cast(int)cast(byte)data[normalOffset + 1],
			                    cast(int)cast(byte)data[normalOffset + 2],
			                    cast(int)cast(byte)data[normalOffset]));
		}
		
		int pointerOffset = modelBlockPointerOffset + modelIndex * 0x10;
		int modelBlockOffset = data.readInt(pointerOffset);
		int verticesOffset = data.readInt(modelBlockOffset);
		//int vertexCount = data.readInt(modelBlockOffset + 4);
		int polygonOffset = data.readInt(modelBlockOffset + 8);
		int polygonCount = data.readInt(modelBlockOffset + 12);
		int normalsOffset = data.readInt(modelBlockOffset + 0x20);
		//int normalsCount = data.readInt(modelBlockOffset + 0x24);

		if (modelBlockOffset == 0) {
			return;
		}
		
		vertices.length = 0;
		ushort v1, v2, v3, v4, n1, n2, n3, n4;
		int curVertOffset, curNormalOffset;

		while (polygonCount > 0)
		{
			v1 = data.readUshort(polygonOffset + 8);
			v2 = data.readUshort(polygonOffset + 10);
			v3 = data.readUshort(polygonOffset + 12);
			v4 = data.readUshort(polygonOffset + 14);

			n1 = data.readUshort(polygonOffset + 0x18);
			n2 = data.readUshort(polygonOffset + 0x1a);
			n3 = data.readUshort(polygonOffset + 0x1c);
			n4 = data.readUshort(polygonOffset + 0x1e);

			// One triangle
			curVertOffset = verticesOffset + v1 * 6;
			curNormalOffset = normalsOffset + n1 * 3;
			vertices ~= getVertex(curVertOffset, polygonOffset, 0, curNormalOffset);
			curVertOffset = verticesOffset + v2 * 6;
			curNormalOffset = normalsOffset + n2 * 3;
			vertices ~= getVertex(curVertOffset, polygonOffset, 1, curNormalOffset);
			curVertOffset = verticesOffset + v3 * 6;
			curNormalOffset = normalsOffset + n3 * 3;
			vertices ~= getVertex(curVertOffset, polygonOffset, 2, curNormalOffset);

			if (v4 != 0xffff) // Two Triangles
			{
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
		texBytes.length = 0;
		int pointerOffset = modelBlockPointerOffset + modelIndex * 0x10;
		int modelBlockOffset = data.readInt(pointerOffset);
		int polygonOffset = data.readInt(modelBlockOffset + 8);
		int polygonCount = data.readInt(modelBlockOffset + 12);
		if (polygonCount <= 0 || modelBlockOffset == 0)
		{
			return;
		}
		modelIndex = modelIndex < 0x1D ? modelIndex : 0x1E; // Wheel texture weirdness
		int textureNum = data[polygonOffset + 4];
		int textureCmdPointers = data.readInt(textureCMDPointersOffset);
		int textureCmdPointer = textureCmdPointers + (modelIndex * 4);
		int textureCmdOffset = data.readInt(textureCmdPointer);

		int textureOffset = data.readInt(textureCmdOffset + 4);

		int maxWidth = textureWidth / 2;
		int maxHeight = textureHeight;
		
		ubyte[] textureIndices;
		textureIndices.length = maxWidth * maxHeight;
		textureIndices[] = data[textureOffset..textureOffset + textureIndices.length];
		ubyte[] modelToPalMap = [0,0,0,1,0,1,0,0,0,0,0,0,0,0,1,1,
		                         0,1,2,4,4,6,6,1,1,1,3,3,3,3,2,2,2,2,2,2];

		int w = 0, h = 0;
		ubyte index;
		auto palette = src.palettes1Binary[(modelToPalMap[modelIndex] * 0x20)..(modelToPalMap[modelIndex] * 0x20) + 0x20];
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