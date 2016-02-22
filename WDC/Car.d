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
			vec3f position;
		}
		
		ubyte[] dataBlob;
		ubyte[] textureBlob;

		private Vertex[] carVertices;
		private mat4f model;
		private GLProgram program;
		private GLVAO vao;
		private GLBuffer vbo;
		private VertexSpecification!Vertex vs;
	}

	this(ubyte[] data, ubyte[] textures)
	{
		dataBlob = data;
		textureBlob = textures;

		createFromBinary(data, textures);
	}

	void enableDrawing(OpenGL opengl, GLProgram prgrm)
	{
		program = prgrm;
		model = mat4f.identity();

		vao = new GLVAO(opengl);
		vbo = new GLBuffer(opengl, GL_ARRAY_BUFFER, GL_STATIC_DRAW, carVertices[]);
		vs = new VertexSpecification!Vertex(program);

		vao.bind();
		vbo.bind();
		vs.use();
		vao.unbind();
	}

	void draw(Camera cam)
	{
		program.uniform("mvpMatrix").set(cam.getPVM(model));
		program.use();
		vao.bind();
		glDrawArrays(GL_POINTS, 0, cast(int)(vbo.size() / vs.vertexSize()));
		vao.unbind();
		program.unuse();
	}

private:
	void createFromBinary(ubyte[] data, ubyte[] textures)
	{
		dataBlob = data;
		
		int pointerOffset = 0xf4;
		int vertexDescriptionOffset = peek!int(dataBlob[pointerOffset..pointerOffset + 4]);
		int vertexOffset = peek!int(dataBlob[vertexDescriptionOffset..vertexDescriptionOffset + 4]);
		int vertexCount = peek!int(dataBlob[vertexDescriptionOffset + 4..vertexDescriptionOffset + 8]);
		int vertexBlockSize = vertexCount * 3 * 2;

		carVertices.length = vertexCount;
		int vertexNum = 0;

		while (vertexNum < vertexCount)
		{
			carVertices[vertexNum] = Vertex(vec3f(cast(float)peek!short(dataBlob[vertexOffset..vertexOffset + 2]),
												cast(float)peek!short(dataBlob[vertexOffset + 4..vertexOffset + 6]),
												cast(float)peek!short(dataBlob[vertexOffset + 2..vertexOffset + 4])));
			vertexNum++;
			vertexOffset += 6;
		}

		//short[] temp = cast(short[])dataBlob[vertexOffset..vertexOffset + vertexBlockSize];
		//carVertices = cast(Vertex[])dataBlob[vertexOffset..vertexOffset + vertexBlockSize];
		//writefln("car test:: %x %x", carVertices[0].position.x, carVertices[0].position.y);
	}

	void createFromModel(ubyte[] data)
	{
		writeln("**** UNIMPLEMENTED ****");
	}
}