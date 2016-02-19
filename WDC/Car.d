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
		ubyte[] dataBlob;

		private struct Vertex
		{
			vec3f position;
		}
		private Vertex[] carModel;
		private mat4f model;
		private GLProgram program;
		private GLVAO vao;
		private GLBuffer vbo;
		private VertexSpecification!Vertex vs;
	}
	// this from binary data
	// this from model data
	// enable drawing (give it opengl and program here so can move out of constructor)
	// draw
	this(OpenGL opengl, GLProgram prgrm, ubyte[] data, Flag!"fromBinary" fromBinary)
	{
		fromBinary ? createFromBinary(data) : createFromModel(data);

		int pointerOffset = 0xf4;
		int vertexDescriptionOffset = peek!int(dataBlob[pointerOffset..pointerOffset + 4]);
		int vertexOffset = peek!int(dataBlob[vertexDescriptionOffset..vertexDescriptionOffset + 4]);
		int vertexCount = peek!int(dataBlob[vertexDescriptionOffset + 4..vertexDescriptionOffset + 8]);
		int vertexBlockSize = vertexCount * 3 * 2;

		carModel.length = vertexCount;
		int vertexNum = 0;

		while (vertexNum < vertexCount)
		{
			carModel[vertexNum] = Vertex(vec3f(cast(float)peek!short(dataBlob[vertexOffset..vertexOffset + 2]),
												cast(float)peek!short(dataBlob[vertexOffset + 4..vertexOffset + 6]),
												cast(float)peek!short(dataBlob[vertexOffset + 2..vertexOffset + 4])));
			vertexNum++;
			vertexOffset += 6;
		}

		//short[] temp = cast(short[])dataBlob[vertexOffset..vertexOffset + vertexBlockSize];
		//carModel = cast(Vertex[])dataBlob[vertexOffset..vertexOffset + vertexBlockSize];
		//writefln("car test:: %x %x", carModel[0].position.x, carModel[0].position.y);

		this.program = prgrm;

		model = mat4f.translation(vec3f(0, 0, 0));

		this.vao = new GLVAO(opengl);

		vbo = new GLBuffer(opengl, GL_ARRAY_BUFFER, GL_STATIC_DRAW, carModel[]);

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
		this.vao.bind();
		glDrawArrays(GL_POINTS, 0, cast(int)(vbo.size() / vs.vertexSize()));
		this.vao.unbind();
		program.unuse();
	}

private:
	void createFromBinary(ubyte[] data)
	{
		dataBlob = data;
		writefln("car test:: %x", peek!short(dataBlob[2..4]));
	}

	void createFromModel(ubyte[] data)
	{
		writeln("**** UNIMPLEMENTED ****");
	}
}