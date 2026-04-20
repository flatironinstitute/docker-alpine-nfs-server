image=127.0.0.1:45703/flatironinstitute/alpine-nfs-server

push: image
	docker push $(image)

image:
	docker build -t $(image) .
