//  Created by Darren Leith on 21/03/2016.
//  Copyright © 2016 Darren Leith. All rights reserved.
//

import UIKit
import CoreData

protocol ViewControllerOneDelegate: class {
	func viewControllerOneDidTapMenuButton(controller: ViewControllerOne)
}

class ViewControllerOne: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UIGestureRecognizerDelegate, MoreOptionsViewControllerDelegate {
	
	//MARK: properties
	
	@IBOutlet weak var collectionView: UICollectionView!
	
	var APODarray = [APOD]()
	var prevOffset: CGFloat = 0.0
	var noAPODsDownloaded = 0
	var currentAPOD = 0
	static var dates: [String] = APODClient.sharedInstance.getAllAPODDates()
	weak var delegate: ViewControllerOneDelegate?
	var apodIndex: NSIndexPath?
	var currentIndexPath: NSIndexPath?
	@IBOutlet weak var barButton: UIBarButtonItem!
	@IBOutlet weak var moreOptionsView: UIView!
	@IBOutlet weak var moreOptionsContainerView: UIView!
	@IBOutlet weak var moreOptionsBarButtonItem: UIBarButtonItem!
	
	
	//MARK: core data
	
	lazy var sharedContext: NSManagedObjectContext = {
		return CoreDataStackManager.sharedInstance.managedObjectContext
	}()
	
	//file path for saving the number of downloaded images
	var noOfDownloadsFilePath : String {
		let manager = NSFileManager.defaultManager()
		let url = manager.URLsForDirectory(.DocumentDirectory, inDomains: .UserDomainMask).first! as NSURL
		return url.URLByAppendingPathComponent("noOfDownloads").path!
	}
	
	//MARK: lifecycle methods
	
	override func viewDidLoad() {
		super.viewDidLoad()
		
		moreOptionsView.alpha = 0.0
		moreOptionsContainerView.hidden = true
	}
	
	override func viewWillAppear(animated: Bool) {
		super.viewWillAppear(animated)
		restoreNoOfDownloads()
		APODarray = fetchAllAPODS()
		
		//if the APOD array is empty we want to fill it with blank cells and download the APOD for today's date
		if APODarray.isEmpty {
			createBlankAPODCells()
			getPhotoProperties([ViewControllerOne.dates.first!])
		}
		
	}
	
	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		collectionView.frame.size = CGSizeMake(view.frame.size.width, view.frame.size.height)
		
		if let index = apodIndex {
			collectionView.scrollToItemAtIndexPath(index, atScrollPosition: .None, animated: false)
			barButton.image = UIImage(named: "leftArrow")
			
		}
		
	}
	
	//MARK: core data
	func fetchAllAPODS() -> [APOD] {
		let fetchRequest = NSFetchRequest(entityName: "APOD")
		do {
		 return try sharedContext.executeFetchRequest(fetchRequest) as! [APOD]
		} catch {
			return [APOD]()
		}
	}
	
	
	//MARK: downloading new photo properties when scrolling
	
	func scrollViewDidEndDecelerating(scrollView: UIScrollView) {
		getImages()
	}
	
	
	func getImages() {
		
		var index: Int = 0
		for cell in collectionView.visibleCells() {
			let i = collectionView.indexPathForCell(cell)!
			index = i.item
		}
		
		print("index of image is: \(index)")
		print("noAPODsDownloaded: \(noAPODsDownloaded)")
		
		if noAPODsDownloaded < index {
			var datesToDownload: [String] = []
			for i in (noAPODsDownloaded + 1)...index {
				datesToDownload.insert(ViewControllerOne.dates[i], atIndex: 0)
			}
			
			print("datesToDownload: \(datesToDownload)")
			
			getPhotoProperties(datesToDownload)
			noAPODsDownloaded = index
			currentAPOD = noAPODsDownloaded
			saveNoOfDownloads()
		}
	}
	
	
	//MARK: download photo properties
	
	func getPhotoProperties(dates: [String]) {
		
		APODClient.sharedInstance.downloadArrayPhotoProperties(dates, completionHandler: { (data, error) in
			
			guard error == nil else {
				print("error in downloading photo array properties")
				return
			}
			
			guard let data: [String: String] = data else {
				print("error retrieving data")
				return
			}
			
			//using the date as the match criteria, compare the downloaded data with the relevant blank APOD cell
			for APOD in self.APODarray {
				
				//ensures the correct APOD is paired with correct cell
				if APOD.dateString == data["date"] {
					APOD.explanation = data["explanation"]
					APOD.title = data["title"]
					APOD.url = data["url"]
					
					if !APOD.url!.containsString("http://apod.nasa.gov/") {
						//typically a video cannot be displayed as an image
						dispatch_async(dispatch_get_main_queue()) {
							APOD.image = UIImage(named: "noPhoto.png")
							self.collectionView.reloadData()
							CoreDataStackManager.sharedInstance.saveContext()
						}
					} else {
						//create an image based on url string
						let url = NSURL(string: APOD.url!)
						let imageData = NSData(contentsOfURL: url!)
						
						dispatch_async(dispatch_get_main_queue()) {
							APOD.image = UIImage(data: imageData!)
							self.collectionView.reloadData()
							CoreDataStackManager.sharedInstance.saveContext()
						}
					}
					return
				}
			}
		})
	}
	
	//MARK: menu button delegate methods
	
	@IBAction func menuButtonTapped(sender: AnyObject) {
		if let _ = apodIndex {
			navigationController?.popToRootViewControllerAnimated(true)
		} else {
			delegate?.viewControllerOneDidTapMenuButton(self)
		}
	}
	
	
	//MARK: collection view
	
	func numberOfSectionsInCollectionView(collectionView: UICollectionView) -> Int {
		return 1
	}
	
	func collectionView(collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
		return APODarray.count
	}
	
	func collectionView(collectionView: UICollectionView, cellForItemAtIndexPath indexPath: NSIndexPath) -> UICollectionViewCell {
		let cell = collectionView.dequeueReusableCellWithReuseIdentifier("APODCollectionViewCell", forIndexPath: indexPath) as! APODCollectionViewCell
		currentIndexPath = indexPath
		configureCell(cell, atIndexPath: indexPath)
		return cell
	}
	
	
	func configureCell(cell: APODCollectionViewCell, atIndexPath indexPath: NSIndexPath) {
		cell.setup()
		
		let APOD = APODarray[indexPath.item]
		cell.setupActivityIndicator(cell)
		
		//if the image has already been downloaded and is in the Documents directory
		if let image = APOD.image {
			//show the toolbar
			cell.titleBottomToolbar.hidden = false
			
			//remove loading image text
			cell.loadingImageText.hidden = true
			
			cell.activityIndicator.stopAnimating()
			cell.imageView.image = image
			cell.imageTitle.text = APOD.title
			cell.explanation = APOD.explanation
			title = formatDateString(APOD.dateString!)
			
			//additional logic for displaying favorites option
			NSNotificationCenter.defaultCenter().postNotificationName("favoriteStatus", object: nil, userInfo: ["isAlreadyFavorite" : APOD.favorite])
			
		} else { //download from the remote serve
			//hide the toolbar
			cell.titleBottomToolbar.hidden = true
			
			//show loading
			cell.loadingImageText.hidden = false
			
			cell.activityIndicator.startAnimating()
			title = ""
			cell.imageView.image = nil
			cell.imageTitle.text = ""
		}
	}
	
	func collectionView(collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAtIndexPath indexPath: NSIndexPath) -> CGSize {
		
		//TODO: remove magic numbers
		return CGSize(width: collectionView.frame.size.width - 10, height: collectionView.frame.size.height - 80)
	}
	
	func collectionView(collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAtIndex section: Int) -> UIEdgeInsets
	{
		return UIEdgeInsetsMake(0, 5, 0, 5)
	}
	
	func collectionView(collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAtIndex section: Int) -> CGFloat {
		return 10
	}
	
	
	//MARK: helper methods
	
	//format the date to be in format e.g. 01 January 20xx
	func formatDateString(date: String) -> String?  {
		let formatter = NSDateFormatter()
		formatter.dateFormat = "yyyy-MM-dd"
		let existingDate = formatter.dateFromString(date)
		let newFormatter = NSDateFormatter()
		newFormatter.dateFormat = "dd MMMM yyyy"
		return newFormatter.stringFromDate(existingDate!)
	}
	
	//create a blank array of APOD cells to populate the collection view. In total ~ 7500 cells created.
	func createBlankAPODCells() {
		//TODO: 50 is not quite right. Must ensure have enough blank cells
		for i in 0..<50 {
			let newAPOD = APOD(dateString: ViewControllerOne.dates[i], context: self.sharedContext)
			APODarray.append(newAPOD)
			CoreDataStackManager.sharedInstance.saveContext()
		}
	}
	
	
	func performUIUpdatesOnMain(updates: () -> Void) {
		dispatch_async(dispatch_get_main_queue()) {
			updates()
		}
	}
	
	//MARK: save and restore number of downloads
	
	func saveNoOfDownloads() {
		let dictionary = [
			"noAPODsDownloaded" : noAPODsDownloaded,
			"currentAPOD"		: currentAPOD
		]
		NSKeyedArchiver.archiveRootObject(dictionary, toFile: noOfDownloadsFilePath)
	}
	
	func restoreNoOfDownloads() {
		if let dictionary = NSKeyedUnarchiver.unarchiveObjectWithFile(noOfDownloadsFilePath) as? [String : AnyObject] {
			noAPODsDownloaded = dictionary["noAPODsDownloaded"] as! Int
			currentAPOD = dictionary["currentAPOD"] as! Int
		}
	}
	
	@IBAction func moreOptionsButtonClicked(sender: UIBarButtonItem) {
		showMoreOptionsDetailView()
	}
	
	func moreOptionsViewControllerSelectFavorite(controller: MoreOptionsViewController, removeFromFavorites: Bool) {
		let apod = APODarray[currentIndexPath!.item]
		
		if removeFromFavorites == true {
			apod.favorite = false
		} else {
			apod.favorite = true
		}
		
		performUIUpdatesOnMain {
			CoreDataStackManager.sharedInstance.saveContext()
			self.collectionView.reloadData()
		}
	}

	
	func moreOptionsViewControllerSelectShare(controller: MoreOptionsViewController) {
		print("share time")
	}
	
	func moreOptionsViewControllerSelectCancel(controller: MoreOptionsViewController) {
		hideMoreOptionsView()
	}
	
	
	override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
		if segue.identifier == "MoreOptionsViewController" {
			let vc = segue.destinationViewController as! MoreOptionsViewController
			vc.delegate = self
		}
	}
	
	func shareImage() {
		//		let activityVC = UIActivityViewController(activityItems: <#T##[AnyObject]#>, applicationActivities: <#T##[UIActivity]?#>)
	}
	
	
	func hideMoreOptionsView() {
		UIView.animateWithDuration(0.5, delay: 0.0, options: [], animations: { () -> Void in
			self.moreOptionsContainerView.center.y += self.view.bounds.height
			self.moreOptionsView.alpha = 0.0
			}, completion: { _ in
				self.moreOptionsContainerView.center.y -= self.view.bounds.height
				self.moreOptionsContainerView.hidden = true
				self.moreOptionsBarButtonItem.enabled = true
		})
	}
	
	func showMoreOptionsDetailView() {
		
		moreOptionsBarButtonItem.enabled = false
		//Animate the detail view to appear on screen
		moreOptionsContainerView.center.y += view.bounds.height
		UIView.animateWithDuration(0.7, delay: 0.0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0, options: [], animations: { () -> Void in
			self.moreOptionsContainerView.center.y -= self.view.bounds.height
			self.moreOptionsView.alpha = 0.7
			}, completion: nil)
		
		
		moreOptionsContainerView.hidden = false
	}
}
