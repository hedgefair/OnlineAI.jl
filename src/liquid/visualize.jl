

function findMatching(viznodes, neuron)
	for viznode in viznodes
		if viznode.neuron === neuron
			return viznode
		end
	end
	error("Couldn't find matching viznode for $neuron")
end


# ---------------------------------------------------------------------------

type LiquidVisualizationNode
	neuron::SpikingNeuron
	circle::SceneItem
end

function LiquidVisualizationNode(neuron::SpikingNeuron, pos::P3)
	# shift x/y coords based on zvalue to give a 3d-ish look
	z = pos[3]
	pos = pos + P3(z/6, z/3, 0)

	# create a new circle in the scene
	radius = 20
	circle = circle!(radius, pos)
	brush!(pen!(circle, 0), :lightGray)
	if !neuron.excitatory
		pen!(circle, 3, :yellow)
	end

	LiquidVisualizationNode(neuron, circle)
end

	# draw lines for synapses
function addSynapticConnections(viznodes::Vector{LiquidVisualizationNode})
	for viznode in viznodes
		for synapse in viznode.neuron.synapses
			connectedViznode = findMatching(viznodes, synapse.postsynapticNeuron)
			l = line!(viznode.circle, connectedViznode.circle)
			pen!(l, 1 + 2 * abs(synapse.weight), 0, 0, 0, 0.3)
		end
	end
end

# ---------------------------------------------------------------------------

function visualize(input::GRFInput, pos::P2, viznodes)
	h = 100
	ys = linspace(-h, h, length(input.neurons))
	pt = P3(pos - P2(70, 0), -10000)
	for (i,neuron) in enumerate(input.neurons)
		viznode = LiquidVisualizationNode(neuron, P3(pos + P2(0,ys[i])))
		push!(viznodes, viznode)
		pen!(line!(viznode.circle, pt), 2, :cyan)  # connect line to pt
	end
	pen!(line!(pt, pt - P3(70,0,0)), 2, :cyan)
end

# ---------------------------------------------------------------------------

type LiquidVisualization
	lsm::LiquidStateMachine
	window::Widget
	scene::Scene
	pltEstVsAct::PlotWidget
	pltScatter::PlotWidget
	viznodes::Vector{LiquidVisualizationNode}
	t::Int
end


function visualize(lsm::LiquidStateMachine)

	nin = lsm.nin
	nout = lsm.nout
	liquid = lsm.liquid

	# set up the liquid scene
	scene = currentScene()
	empty!(scene)
	background!(:gray)
	viznodes = LiquidVisualizationNode[]

	# input
	nin = length(lsm.inputs.inputs)
	startpos = P2(-400, -400)
	diffpos = P2(0, -startpos[2])
	for (i,input) in enumerate(lsm.inputs.inputs)
		pos = startpos + diffpos .* (nin > 1 ? (i-1) / (nin-1) : 0.5)
		visualize(input, pos, viznodes)
	end

	# liquid
	startpos = P3(-150,-150,-300)
	diffpos = -2 * startpos
	liquidsz = (liquid.params.l, liquid.params.w, liquid.params.h)
	for neuron in liquid.neurons
		pct = (P3(neuron.position...) - 1) ./ (P3(liquidsz...) - 1)
		pos = startpos + pct .* diffpos
		push!(viznodes, LiquidVisualizationNode(neuron, pos))
	end

	addSynapticConnections(viznodes)

	# set up the estimate vs actual plot
	pltEstVsAct = plot(zeros(0,nout*2),
										 title="predicted vs actual",
										 labels = map(i->string(i<=nout ? "Act" : "Est", i), 1:nout*2),
										 show=false)
	# oplot(pltEstVsAct, zeros(0,nout), labels = map(x->"Est$x", 1:nout))

	# set up the scatter plot of estimate vs actual
	pltScatter = scatter(zeros(0,nout),
											 zeros(0,nout),
											 xlabel = "predicted",
											 ylabel = "actual",
											 show=false)

	# put all 3 together into a widget container, resize, then show
	window = vsplitter(hsplitter(scene, pltScatter), pltEstVsAct)
	Qwt.moveWindowToCenterScreen(window)
	resizewidget(window, P2(2000,1500))
	showwidget(window)

	LiquidVisualization(lsm, window, scene, pltEstVsAct, pltScatter, viznodes, 0)
end

#update visualization
function OnlineStats.update!(viz::LiquidVisualization, y::VecF)
	viz.t += 1

	for viznode in viz.viznodes
		neuron = viznode.neuron
		local args
		if neuron.fired
			args = (:red,)
		else
			upct = 1 - neuron.u / neuron.ϑ
			args = (upct,upct,upct)
		end
		brush!(viznode.circle, args...)
	end

	est = predict(viz.lsm)
	for (i,e) in enumerate(est)
		push!(viz.pltEstVsAct, i, viz.t, y[i])
		push!(viz.pltEstVsAct, i+viz.lsm.nout, viz.t, e)
		push!(viz.pltScatter, i, e, y[i])
	end
	refresh(viz.pltEstVsAct)
	refresh(viz.pltScatter)

	sleep(0.0001)
end