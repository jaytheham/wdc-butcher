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
			vec3i position;
			vec4ub colour;
			//vec2f vertexUV;
			//vec3i inNormal;
		}
		Vertex[] trackVertices;
		Vertex[] sectionVertices;
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
		setupBuffers(trackVertices);
	}

	void setupBuffers(Vertex[] vertices)
	{
		sectionVAO = new GLVAO(openGL);
		sectionVAO.bind();
		sectionVBO = new GLBuffer(openGL, GL_ARRAY_BUFFER, GL_STATIC_DRAW, trackVertices[]);
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
		
		foreach(trackSection; source.trackSections)
		{
			foreach(modelInfo; trackSection.models)
			{

				origin = vec3i(convertOrigin(modelInfo.originX),
				               convertOrigin(modelInfo.originY),
				               convertOrigin(modelInfo.originZ));

				foreach(polygon; modelInfo.polygons)
				{
					trackVertices ~= Vertex(vec3i(modelInfo.vertices[polygon.vertexIndexOne].X,
					                              modelInfo.vertices[polygon.vertexIndexOne].Y,
					                              modelInfo.vertices[polygon.vertexIndexOne].Z) + origin,
					                              modelInfo.colours[polygon.vertexOneColourIndex]);
					trackVertices ~= Vertex(vec3i(modelInfo.vertices[polygon.vertexIndexTwo].X,
					                              modelInfo.vertices[polygon.vertexIndexTwo].Y,
					                              modelInfo.vertices[polygon.vertexIndexTwo].Z) + origin,
					                              modelInfo.colours[polygon.vertexTwoColourIndex]);
					trackVertices ~= Vertex(vec3i(modelInfo.vertices[polygon.vertexIndexThree].X,
					                              modelInfo.vertices[polygon.vertexIndexThree].Y,
					                              modelInfo.vertices[polygon.vertexIndexThree].Z) + origin,
					                              modelInfo.colours[polygon.vertexThreeColourIndex]);
					if (polygon.vertexIndexFour != 0xffff)
					{
						trackVertices ~= Vertex(vec3i(modelInfo.vertices[polygon.vertexIndexOne].X,
						                              modelInfo.vertices[polygon.vertexIndexOne].Y,
						                              modelInfo.vertices[polygon.vertexIndexOne].Z) + origin,
					                                  modelInfo.colours[polygon.vertexOneColourIndex]);
						trackVertices ~= Vertex(vec3i(modelInfo.vertices[polygon.vertexIndexThree].X,
						                              modelInfo.vertices[polygon.vertexIndexThree].Y,
						                              modelInfo.vertices[polygon.vertexIndexThree].Z) + origin,
					                                  modelInfo.colours[polygon.vertexThreeColourIndex]);
						trackVertices ~= Vertex(vec3i(modelInfo.vertices[polygon.vertexIndexFour].X,
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
		
		foreach(modelInfo; source.trackSections[0].models)
		{
			foreach(polygon; modelInfo.polygons)
			{
				sectionVertices ~= Vertex(vec3i(modelInfo.vertices[polygon.vertexIndexOne].X,
				                                modelInfo.vertices[polygon.vertexIndexOne].Y,
				                                modelInfo.vertices[polygon.vertexIndexOne].Z));
				sectionVertices ~= Vertex(vec3i(modelInfo.vertices[polygon.vertexIndexTwo].X,
				                                modelInfo.vertices[polygon.vertexIndexTwo].Y,
				                                modelInfo.vertices[polygon.vertexIndexTwo].Z));
				sectionVertices ~= Vertex(vec3i(modelInfo.vertices[polygon.vertexIndexThree].X,
				                                modelInfo.vertices[polygon.vertexIndexThree].Y,
				                                modelInfo.vertices[polygon.vertexIndexThree].Z));
				if (polygon.vertexIndexFour != 0xffff)
				{
					sectionVertices ~= Vertex(vec3i(modelInfo.vertices[polygon.vertexIndexOne].X,
					                            modelInfo.vertices[polygon.vertexIndexOne].Y,
					                            modelInfo.vertices[polygon.vertexIndexOne].Z));
					sectionVertices ~= Vertex(vec3i(modelInfo.vertices[polygon.vertexIndexThree].X,
					                            modelInfo.vertices[polygon.vertexIndexThree].Y,
					                            modelInfo.vertices[polygon.vertexIndexThree].Z));
					sectionVertices ~= Vertex(vec3i(modelInfo.vertices[polygon.vertexIndexFour].X,
					                            modelInfo.vertices[polygon.vertexIndexFour].Y,
					                            modelInfo.vertices[polygon.vertexIndexFour].Z));
				}
			}
		}
	}

	void draw(Camera cam)
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
			in ivec3 position;
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