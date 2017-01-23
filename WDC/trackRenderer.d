module wdc.trackRenderer;

import camera,
	   gfm.math,
	   gfm.opengl,
	   wdc.track,
	   wdc.renderer;
import std.stdio;

class TrackRenderer : Renderer
{
	private
	{
		Track source;

		GLProgram program;
		OpenGL openGL;
		mat4f model;
		VertexSpecification!Vertex vs;

		GLVAO sectionVAO;
		GLBuffer sectionVBO;

		struct Vertex
		{
			vec3f position;
			vec4ub colour = vec4ub(cast(ubyte)0xff, cast(ubyte)0xff, cast(ubyte)0xff, cast(ubyte)0xff);
			//vec2f vertexUV;
			//vec3i inNormal;
		}
		Vertex[] trackVertices;
		Vertex[] sectionVertices;
		Vertex[] collisionVertices;
	}

	this(Track sourceTrack, OpenGL openglInstance)
	{
		source = sourceTrack;
		program = createShader(openglInstance);
		openGL = openglInstance;
		model = mat4f.identity();
		vs = new VertexSpecification!Vertex(program);

		//loadSectionVertices();
		loadTrackVertices();
		//loadCollisionVertices();
		setupBuffers(trackVertices);
	}

	void setupBuffers(Vertex[] vertices)
	{
		sectionVAO = new GLVAO(openGL);
		sectionVAO.bind();
		sectionVBO = new GLBuffer(openGL, GL_ARRAY_BUFFER, GL_STATIC_DRAW, vertices[]);
		sectionVAO.unbind();

		sectionVBO.setData(vertices[]);
	}

	int convertOrigin(int coord)
	{
		assert((coord & 0xff) == 0, "Low byte is not what we thought it was Jim");
		return coord / 2048;
	}

	void loadTrackVertices()
	{
		vec3i origin;
		trackVertices.length = 0;
		
		foreach(trackMeshSection; source.trackMeshSections)
		{
			foreach(modelInfo; trackMeshSection.models)
			{

				origin = vec3i(convertOrigin(modelInfo.originX),
				               convertOrigin(modelInfo.originY),
				               convertOrigin(modelInfo.originZ));

				foreach(polygon; modelInfo.polygons)
				{
					trackVertices ~= Vertex(vec3f(modelInfo.vertices[polygon.vertexIndexOne].X,
					                              modelInfo.vertices[polygon.vertexIndexOne].Y,
					                              modelInfo.vertices[polygon.vertexIndexOne].Z) + origin,
					                              modelInfo.colours[polygon.vertexOneColourIndex]);
					trackVertices ~= Vertex(vec3f(modelInfo.vertices[polygon.vertexIndexTwo].X,
					                              modelInfo.vertices[polygon.vertexIndexTwo].Y,
					                              modelInfo.vertices[polygon.vertexIndexTwo].Z) + origin,
					                              modelInfo.colours[polygon.vertexTwoColourIndex]);
					trackVertices ~= Vertex(vec3f(modelInfo.vertices[polygon.vertexIndexThree].X,
					                              modelInfo.vertices[polygon.vertexIndexThree].Y,
					                              modelInfo.vertices[polygon.vertexIndexThree].Z) + origin,
					                              modelInfo.colours[polygon.vertexThreeColourIndex]);
					if (polygon.vertexIndexFour != 0xffff)
					{
						trackVertices ~= Vertex(vec3f(modelInfo.vertices[polygon.vertexIndexOne].X,
						                              modelInfo.vertices[polygon.vertexIndexOne].Y,
						                              modelInfo.vertices[polygon.vertexIndexOne].Z) + origin,
					                                  modelInfo.colours[polygon.vertexOneColourIndex]);
						trackVertices ~= Vertex(vec3f(modelInfo.vertices[polygon.vertexIndexThree].X,
						                              modelInfo.vertices[polygon.vertexIndexThree].Y,
						                              modelInfo.vertices[polygon.vertexIndexThree].Z) + origin,
					                                  modelInfo.colours[polygon.vertexThreeColourIndex]);
						trackVertices ~= Vertex(vec3f(modelInfo.vertices[polygon.vertexIndexFour].X,
						                              modelInfo.vertices[polygon.vertexIndexFour].Y,
						                              modelInfo.vertices[polygon.vertexIndexFour].Z) + origin,
					                                  modelInfo.colours[polygon.vertexFourColourIndex]);
					}
				}
			}
		}
	}

	void loadSectionVertices()
	{
		sectionVertices.length = 0;
		
		foreach(modelInfo; source.trackMeshSections[0].models)
		{
			foreach(polygon; modelInfo.polygons)
			{
				sectionVertices ~= Vertex(vec3f(modelInfo.vertices[polygon.vertexIndexOne].X,
				                                modelInfo.vertices[polygon.vertexIndexOne].Y,
				                                modelInfo.vertices[polygon.vertexIndexOne].Z));
				sectionVertices ~= Vertex(vec3f(modelInfo.vertices[polygon.vertexIndexTwo].X,
				                                modelInfo.vertices[polygon.vertexIndexTwo].Y,
				                                modelInfo.vertices[polygon.vertexIndexTwo].Z));
				sectionVertices ~= Vertex(vec3f(modelInfo.vertices[polygon.vertexIndexThree].X,
				                                modelInfo.vertices[polygon.vertexIndexThree].Y,
				                                modelInfo.vertices[polygon.vertexIndexThree].Z));
				if (polygon.vertexIndexFour != 0xffff)
				{
					sectionVertices ~= Vertex(vec3f(modelInfo.vertices[polygon.vertexIndexOne].X,
					                            modelInfo.vertices[polygon.vertexIndexOne].Y,
					                            modelInfo.vertices[polygon.vertexIndexOne].Z));
					sectionVertices ~= Vertex(vec3f(modelInfo.vertices[polygon.vertexIndexThree].X,
					                            modelInfo.vertices[polygon.vertexIndexThree].Y,
					                            modelInfo.vertices[polygon.vertexIndexThree].Z));
					sectionVertices ~= Vertex(vec3f(modelInfo.vertices[polygon.vertexIndexFour].X,
					                            modelInfo.vertices[polygon.vertexIndexFour].Y,
					                            modelInfo.vertices[polygon.vertexIndexFour].Z));
				}
			}
		}
	}

	void loadCollisionVertices()
	{
		collisionVertices.length = 0;
		vec4ub[6] clrs;
		clrs[0] = vec4ub(cast(ubyte)(0x0),cast(ubyte)(0x0),cast(ubyte)(0xff), cast(ubyte)0xff);
		clrs[1] = vec4ub(cast(ubyte)(0x0),cast(ubyte)(0xff),cast(ubyte)(0x00), cast(ubyte)0xff);
		clrs[2] = vec4ub(cast(ubyte)(0xff),cast(ubyte)(0x0),cast(ubyte)(0x00), cast(ubyte)0xff);
		clrs[3] = vec4ub(cast(ubyte)(0x0),cast(ubyte)(0xff),cast(ubyte)(0xff), cast(ubyte)0xff);
		clrs[4] = vec4ub(cast(ubyte)(0xff),cast(ubyte)(0x0),cast(ubyte)(0xff), cast(ubyte)0xff);
		clrs[5] = vec4ub(cast(ubyte)(0xff),cast(ubyte)(0xff),cast(ubyte)(0x0), cast(ubyte)0xff);
		
		foreach(i, collisionSection; source.trackCollisionSections)
		{
			clrs[0] = vec4ub(cast(ubyte)(collisionSection.unknownBs.length * 16),cast(ubyte)(0x0),cast(ubyte)(0xff), cast(ubyte)0xff);
			foreach(polygon; collisionSection.polygons)
			{
				collisionVertices ~= Vertex(vec3f(collisionSection.vertices[polygon.vertexIndexOne].x,
				                                  collisionSection.vertices[polygon.vertexIndexOne].y,
				                                  collisionSection.vertices[polygon.vertexIndexOne].z),
				clrs[0]);
				//                                  collisionSection.vertices[polygon.vertexIndexOne].lightColour);
				collisionVertices ~= Vertex(vec3f(collisionSection.vertices[polygon.vertexIndexTwo].x,
				                                  collisionSection.vertices[polygon.vertexIndexTwo].y,
				                                  collisionSection.vertices[polygon.vertexIndexTwo].z),
				clrs[0]);
				//                                  collisionSection.vertices[polygon.vertexIndexTwo].lightColour);
				collisionVertices ~= Vertex(vec3f(collisionSection.vertices[polygon.vertexIndexThree].x,
				                                  collisionSection.vertices[polygon.vertexIndexThree].y,
				                                  collisionSection.vertices[polygon.vertexIndexThree].z),
				clrs[0]);
				//                                  collisionSection.vertices[polygon.vertexIndexThree].lightColour);
			}
		}
	}

	void draw(Camera cam, char[] args)
	{
		program.uniform("mvpMatrix").set(cam.getPVM(model));
		program.use();
		sectionVAO.bind();
		vs.use();
		glDrawArrays(GL_TRIANGLES, 0, trackVertices.length);
		sectionVAO.unbind();
		program.unuse();
	}

	private auto createShader(OpenGL opengl)
	{
		string tunnelProgramSource =
			q{#version 330 core

			#if VERTEX_SHADER
			in vec3 position;
			in ivec4 colour;

			out vec4 outColour;

			uniform mat4 mvpMatrix;
			void main()
			{
				gl_Position = mvpMatrix * vec4(position, 1.0);
				outColour = vec4(colour.r / 255.0, colour.g / 255.0, colour.b / 255.0, colour.a / 255.0);
			}
			#endif

			#if FRAGMENT_SHADER
			in vec4 outColour;
			out vec4 color;

			void main()
			{
				color = outColour;
			}
			#endif
		};

		return new GLProgram(opengl, tunnelProgramSource);
	}
}