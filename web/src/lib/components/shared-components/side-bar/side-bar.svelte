<script lang="ts">
	import { page } from '$app/stores';
	import { api } from '@api';
	import AccountMultipleOutline from 'svelte-material-icons/AccountMultipleOutline.svelte';
	import ImageAlbum from 'svelte-material-icons/ImageAlbum.svelte';
	import ImageOutline from 'svelte-material-icons/ImageOutline.svelte';
	import InformationOutline from 'svelte-material-icons/InformationOutline.svelte';
	import StarOutline from 'svelte-material-icons/StarOutline.svelte';
	import { fade } from 'svelte/transition';
	import { AppRoute } from '../../../constants';
	import LoadingSpinner from '../loading-spinner.svelte';
	import StatusBox from '../status-box.svelte';
	import SideBarButton from './side-bar-button.svelte';

	let showAssetCount = false;
	let showSharingCount = false;
	let showFavoritesCount = false;
	let showAlbumsCount = false;

	const getAssetCount = async () => {
		const { data: assetCount } = await api.assetApi.getAssetCountByUserId();

		return {
			videos: assetCount.videos,
			photos: assetCount.photos
		};
	};

	const getFavoriteCount = async () => {
		const { data: assets } = await api.assetApi.getAllAssets(true);

		return {
			favorites: assets.length
		};
	};

	const getAlbumCount = async () => {
		const { data: albumCount } = await api.albumApi.getAlbumCountByUserId();
		return {
			shared: albumCount.shared,
			sharing: albumCount.sharing,
			owned: albumCount.owned
		};
	};

	const locale = navigator.language;
</script>

<section id="sidebar" class="flex flex-col gap-1 pt-8 pr-6 bg-immich-bg dark:bg-immich-dark-bg">
	<a
		data-sveltekit-preload-data="hover"
		data-sveltekit-noscroll
		href={AppRoute.PHOTOS}
		class="relative"
		draggable="false"
	>
		<SideBarButton
			title={`Photos`}
			logo={ImageOutline}
			isSelected={$page.route.id === AppRoute.PHOTOS}
		/>
		<div
			id="asset-count-info"
			class="absolute right-4 top-[15px] z-40 text-xs hover:cursor-help"
			on:mouseenter={() => (showAssetCount = true)}
			on:mouseleave={() => (showAssetCount = false)}
		>
			<InformationOutline size={18} color="#989a9f" />
			{#if showAssetCount}
				<div
					transition:fade={{ duration: 200 }}
					class="w-32 rounded-lg p-4 shadow-lg bg-white absolute -right-[135px] top-0 z-[9999] flex place-items-center place-content-center"
				>
					{#await getAssetCount()}
						<LoadingSpinner />
					{:then data}
						<div>
							<p>{data.videos.toLocaleString(locale)} Videos</p>
							<p>{data.photos.toLocaleString(locale)} Photos</p>
						</div>
					{/await}
				</div>
			{/if}
		</div>
	</a>

	<a data-sveltekit-preload-data="hover" href={AppRoute.SHARING} class="relative" draggable="false">
		<SideBarButton
			title="Sharing"
			logo={AccountMultipleOutline}
			isSelected={$page.route.id === AppRoute.SHARING}
		/>
		<div
			id="sharing-count-info"
			class="absolute right-4 top-[15px] z-40 text-xs hover:cursor-help"
			on:mouseenter={() => (showSharingCount = true)}
			on:mouseleave={() => (showSharingCount = false)}
		>
			<InformationOutline size={18} color="#989a9f" />
			{#if showSharingCount}
				<div
					transition:fade={{ duration: 200 }}
					class="w-24 rounded-lg p-4 shadow-lg bg-white absolute -right-[105px] top-0 z-[9999] flex place-items-center place-content-center"
				>
					{#await getAlbumCount()}
						<LoadingSpinner />
					{:then data}
						<div>
							<p>{(data.shared + data.sharing).toLocaleString(locale)} Albums</p>
						</div>
					{/await}
				</div>
			{/if}
		</div>
	</a>
	<div class="text-xs ml-5 my-4 dark:text-immich-dark-fg">
		<p>LIBRARY</p>
	</div>
	<a
		data-sveltekit-preload-data="hover"
		href={AppRoute.FAVORITES}
		class="relative"
		draggable="false"
	>
		<SideBarButton
			title="Favorites"
			logo={StarOutline}
			isSelected={$page.route.id == AppRoute.FAVORITES}
		/>

		<div
			id="favorite-count-info"
			class="absolute right-4 top-[15px] z-40 text-xs hover:cursor-help"
			on:mouseenter={() => (showFavoritesCount = true)}
			on:mouseleave={() => (showFavoritesCount = false)}
		>
			<InformationOutline size={18} color="#989a9f" />
			{#if showFavoritesCount}
				<div
					transition:fade={{ duration: 200 }}
					id="asset-count-info-detail"
					class="w-32 rounded-lg p-4 shadow-lg bg-white absolute -right-[135px] top-0 z-[9999] flex place-items-center place-content-center"
				>
					{#await getFavoriteCount()}
						<LoadingSpinner />
					{:then data}
						<div>
							<p>{data.favorites} Favorites</p>
						</div>
					{/await}
				</div>
			{/if}
		</div>
	</a>
	<a data-sveltekit-preload-data="hover" href={AppRoute.ALBUMS} class="relative" draggable="false">
		<SideBarButton
			title="Albums"
			logo={ImageAlbum}
			isSelected={$page.route.id === AppRoute.ALBUMS}
		/>

		<div
			id="album-count-info"
			class="absolute right-4 top-[15px] z-40 text-xs hover:cursor-help"
			on:mouseenter={() => (showAlbumsCount = true)}
			on:mouseleave={() => (showAlbumsCount = false)}
		>
			<InformationOutline size={18} color="#989a9f" />
			{#if showAlbumsCount}
				<div
					transition:fade={{ duration: 200 }}
					id="asset-count-info-detail"
					class="w-24 rounded-lg p-4 shadow-lg bg-white absolute -right-[105px] top-0 z-[9999] flex place-items-center place-content-center"
				>
					{#await getAlbumCount()}
						<LoadingSpinner />
					{:then data}
						<div>
							<p>{data.owned.toLocaleString(locale)} Albums</p>
						</div>
					{/await}
				</div>
			{/if}
		</div>
	</a>

	<!-- Status Box -->
	<div class="mb-6 mt-auto">
		<StatusBox />
	</div>
</section>
