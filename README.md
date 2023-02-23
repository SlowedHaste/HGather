# HGather
This is a simple dig tracker for FFXI. This addon works with Ashita v4. 


## Commands
/hgather open - Opens the window showing dig data

/hgather close - Closes the window showing dig data

/hgather update - Updates the pricing for items based on the itempricing.txt file

/hgather reset - Resets the digging data

## Pricing
Pricing for items is listed under the itempricing.txt file. This can be updated with any text editor, make sure the format is as follows:

**Format**: itemname:itemprice

**Example:** pebble:100

This would price pebbles at 100g.  Make sure there are no spaces in any of the lines.

If you update the prices while in game, make sure to use the **/hgather update** command to update the prices.

