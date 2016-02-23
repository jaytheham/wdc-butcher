module wdc.car;

import std.stdio,
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
		}

		ubyte[] dataBlob;
		ubyte[] textureBlob;
		Vertex[] carVertices;
		ushort[] carIndices;
		mat4f model;
		GLProgram program;
		OpenGL openGL;
		GLVAO vao;
		GLBuffer vbo;
		GLBuffer vibo;
		VertexSpecification!Vertex vs;

		int modelBlockIndex = 0;
		int numModelBlocks = 0;

		enum modelBlockPointerOffset = 0xf4;
	}

	this(ubyte[] data, ubyte[] textures)
	{
		dataBlob = data;
		textureBlob = textures;

		createFromBinary(data, textures);
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
		program.uniform("mvpMatrix").set(cam.getPVM(model));
		program.use();
		vao.bind();
		//glDrawArrays(GL_POINTS, 0, cast(int)(vbo.size() / vs.vertexSize()));
		glDrawElements(GL_TRIANGLES, carIndices.length, GL_UNSIGNED_SHORT, cast(void*)0);
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

private:
	void createFromBinary(ubyte[] data, ubyte[] textures)
	{
		dataBlob = data;
		textureBlob = textures;

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
		//vao.bind();
		vbo.setData(carVertices[]);
		vibo.setData(carIndices[]);
		//vao.unbind();
	}

	void setupBuffers()
	{
		vao = new GLVAO(openGL);
		vao.bind();
		vbo = new GLBuffer(openGL, GL_ARRAY_BUFFER, GL_STATIC_DRAW, carVertices[]);
		vibo = new GLBuffer(openGL, GL_ELEMENT_ARRAY_BUFFER, GL_STATIC_DRAW, carIndices[]);
		vs.use();
		vao.unbind();
	}

	void loadModelData()
	{
		loadVertices();
		loadIndices();

		if (carVertices.length < 3 || carIndices.length < 3)
		{
			writeln("NOTE: Too few vertices or indices defined to draw anything");
		}
	}

	void loadVertices()
	{
		int pointerOffset = modelBlockPointerOffset + modelBlockIndex * 0x10;
		int modelDescriptionOffset = peek!int(dataBlob[pointerOffset..pointerOffset + 4]);
		int vertexOffset = peek!int(dataBlob[modelDescriptionOffset..modelDescriptionOffset + 4]);
		int vertexCount = peek!int(dataBlob[modelDescriptionOffset + 4..modelDescriptionOffset + 8]);
		int vertexBlockSize = vertexCount * 3 * 2;
		writefln(":: %x", modelDescriptionOffset);

		carVertices.length = vertexCount;
		int vertexNum = 0;

		while (vertexNum < vertexCount)
		{
			carVertices[vertexNum] = Vertex(vec3i(peek!short(dataBlob[vertexOffset..vertexOffset + 2]),
												peek!short(dataBlob[vertexOffset + 4..vertexOffset + 6]),
												peek!short(dataBlob[vertexOffset + 2..vertexOffset + 4])));
			vertexNum++;
			vertexOffset += 6;
		}

		//short[] temp = cast(short[])dataBlob[vertexOffset..vertexOffset + vertexBlockSize];
		//carVertices = cast(Vertex[])dataBlob[vertexOffset..vertexOffset + vertexBlockSize];
		//writefln("car test:: %x %x", carVertices[0].position.x, carVertices[0].position.y);
	}

	void loadIndices()
	{
		int pointerOffset = modelBlockPointerOffset + modelBlockIndex * 0x10;
		int modelDescriptionOffset = peek!int(dataBlob[pointerOffset..pointerOffset + 4]);
		int polygonOffset = peek!int(dataBlob[modelDescriptionOffset + 8 .. modelDescriptionOffset + 12]);
		int polygonCount = peek!int(dataBlob[modelDescriptionOffset + 12 .. modelDescriptionOffset + 16]);
		
		ushort v1, v2, v3, v4;

		carIndices.length = 0;

		while (polygonCount > 0)
		{
			v1 = peek!ushort(dataBlob[polygonOffset + 8 .. polygonOffset + 10]);
			v2 = peek!ushort(dataBlob[polygonOffset + 10 .. polygonOffset + 12]);
			v3 = peek!ushort(dataBlob[polygonOffset + 12 .. polygonOffset + 14]);
			v4 = peek!ushort(dataBlob[polygonOffset + 14 .. polygonOffset + 16]);

			if (v4 == 0xffff) // One triangle
			{
				carIndices ~= v1;
				carIndices ~= v2;
				carIndices ~= v3;
			}
			else // Two Triangles
			{
				carIndices ~= v1;
				carIndices ~= v2;
				carIndices ~= v3;

				carIndices ~= v1;
				carIndices ~= v3;
				carIndices ~= v4;
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